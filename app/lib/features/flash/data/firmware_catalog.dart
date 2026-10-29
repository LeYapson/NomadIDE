import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Carte pour laquelle on sait trouver un firmware MicroPython officiel.
enum FirmwareBoard {
  esp32('ESP32', FirmwareFile.bin, micropythonId: 'ESP32_GENERIC'),
  esp32s3('ESP32-S3', FirmwareFile.bin, micropythonId: 'ESP32_GENERIC_S3'),
  esp32c3('ESP32-C3', FirmwareFile.bin, micropythonId: 'ESP32_GENERIC_C3'),
  esp32s2('ESP32-S2', FirmwareFile.bin, micropythonId: 'ESP32_GENERIC_S2'),
  esp32c6('ESP32-C6', FirmwareFile.bin, micropythonId: 'ESP32_GENERIC_C6'),
  pico('Raspberry Pi Pico', FirmwareFile.uf2, micropythonId: 'RPI_PICO'),
  picoW('Raspberry Pi Pico W', FirmwareFile.uf2, micropythonId: 'RPI_PICO_W'),
  badger2040('Pimoroni Badger 2040', FirmwareFile.uf2, pimoroniAsset: 'pimoroni-badger2040-'),
  badger2040w('Pimoroni Badger 2040 W', FirmwareFile.uf2, pimoroniAsset: 'pimoroni-badger2040w-');

  const FirmwareBoard(this.label, this.file, {this.micropythonId, this.pimoroniAsset});

  final String label;
  final FirmwareFile file;

  /// Identifiant de la carte sur micropython.org/download/.
  final String? micropythonId;

  /// Début du nom du fichier dans les releases de pimoroni/badger2040.
  final String? pimoroniAsset;
}

enum FirmwareFile { bin, uf2 }

/// Dernière version stable trouvée pour une carte.
class FirmwareRelease {
  const FirmwareRelease({required this.board, required this.version, required this.url, required this.fileName, this.date});

  final FirmwareBoard board;

  /// Ex. `v1.29.0`.
  final String version;
  final Uri url;
  final String fileName;

  /// Date de la version (AAAAMMJJ), quand le site la donne.
  final String? date;
}

enum FirmwareError {
  /// Pas de réseau, ou serveur injoignable. Paramètre : `cause`.
  network,

  /// Aucune version stable ne correspond à la carte.
  notFound,

  /// Le serveur n'a pas répondu 200. Paramètre : `status`.
  badStatus,

  /// Fichier plus gros que la limite. Paramètre : `size`.
  tooLarge,

  /// Adresse non autorisée (pas HTTPS, ou hors des sites officiels).
  untrustedSource,
}

class FirmwareException implements Exception {
  const FirmwareException(this.error, {required this.host, this.cause, this.status, this.size});

  final FirmwareError error;
  final String host;
  final Object? cause;
  final int? status;
  final int? size;

  @override
  String toString() => 'FirmwareException($error, $host${cause == null ? '' : ', $cause'})';
}

/// Accès réseau, séparé pour être remplacé dans les tests.
abstract interface class FirmwareSource {
  Future<String> fetchText(Uri url);

  Future<Uint8List> fetchBytes(Uri url, {void Function(int done, int? total)? onProgress});
}

/// Téléchargement HTTPS direct (dart:io), sans dépendance.
class HttpFirmwareSource implements FirmwareSource {
  HttpFirmwareSource({this.timeout = const Duration(seconds: 20), this.maxBytes = FirmwareCatalog.maxFirmwareBytes});

  final Duration timeout;
  final int maxBytes;

  @override
  Future<String> fetchText(Uri url) async => utf8.decode(await fetchBytes(url, maxBytesOverride: 4 * 1024 * 1024), allowMalformed: true);

  @override
  Future<Uint8List> fetchBytes(Uri url, {void Function(int done, int? total)? onProgress, int? maxBytesOverride}) async {
    final limit = maxBytesOverride ?? maxBytes;
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.getUrl(url).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'NomadIDE');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) {
        throw FirmwareException(FirmwareError.badStatus, host: url.host, status: response.statusCode);
      }
      final total = response.contentLength >= 0 ? response.contentLength : null;
      if (total != null && total > limit) {
        throw FirmwareException(FirmwareError.tooLarge, host: url.host, size: total);
      }
      final out = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        out.add(chunk);
        if (out.length > limit) throw FirmwareException(FirmwareError.tooLarge, host: url.host, size: out.length);
        onProgress?.call(out.length, total);
      }
      return out.takeBytes();
    } on FirmwareException {
      rethrow;
    } on Object catch (e) {
      throw FirmwareException(FirmwareError.network, host: url.host, cause: e);
    } finally {
      client.close(force: true);
    }
  }
}

/// Trouve et télécharge les firmwares MicroPython officiels.
///
/// Sources : micropython.org pour les cartes ESP32 et Raspberry Pi Pico, les releases GitHub de
/// pimoroni/badger2040 pour les Badger. Seuls ces sites, en HTTPS, sont acceptés ; les versions de
/// développement (« preview ») sont ignorées.
class FirmwareCatalog {
  FirmwareCatalog(this._source);

  final FirmwareSource _source;

  /// Aucun firmware de ces cartes ne dépasse quelques Mo : au-delà, on refuse.
  static const int maxFirmwareBytes = 16 * 1024 * 1024;

  static const Set<String> trustedHosts = {'micropython.org', 'github.com', 'api.github.com'};

  static final Uri _badgerReleases = Uri.https('api.github.com', '/repos/pimoroni/badger2040/releases/latest');

  Future<FirmwareRelease> latest(FirmwareBoard board) {
    return board.micropythonId != null ? _fromMicroPython(board) : _fromPimoroni(board);
  }

  Future<FirmwareRelease> _fromMicroPython(FirmwareBoard board) async {
    final id = board.micropythonId!;
    final page = Uri.https('micropython.org', '/download/$id/');
    final html = await _source.fetchText(_checked(page));

    // `<ID>-<date>-<version>.<ext>` : l'identifiant suivi directement de la date écarte les variantes
    // (UNICORE, OTA, SPIRAM…), et l'extension collée à la version écarte les « preview ».
    final extension = board.file.name;
    final pattern = RegExp('/resources/firmware/${RegExp.escape(id)}-(\\d{8})-(v\\d+(?:\\.\\d+)*)\\.$extension');
    String? bestDate;
    String? bestVersion;
    for (final m in pattern.allMatches(html)) {
      final date = m.group(1)!;
      if (bestDate == null || date.compareTo(bestDate) > 0) {
        bestDate = date;
        bestVersion = m.group(2)!;
      }
    }
    if (bestDate == null) throw FirmwareException(FirmwareError.notFound, host: page.host);

    final fileName = '$id-$bestDate-$bestVersion.$extension';
    return FirmwareRelease(
      board: board,
      version: bestVersion!,
      date: bestDate,
      fileName: fileName,
      url: _checked(Uri.https('micropython.org', '/resources/firmware/$fileName')),
    );
  }

  Future<FirmwareRelease> _fromPimoroni(FirmwareBoard board) async {
    final json = jsonDecode(await _source.fetchText(_checked(_badgerReleases)));
    final assets = json is Map ? json['assets'] : null;
    final tag = json is Map ? json['tag_name'] : null;
    if (assets is! List || tag is! String) throw FirmwareException(FirmwareError.notFound, host: _badgerReleases.host);

    // « …-micropython.uf2 » (sans « with-badger-os ») : le firmware seul, avec les modules d'affichage.
    final prefix = board.pimoroniAsset!;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      if (name is String && url is String && name.startsWith(prefix) && name.endsWith('-micropython.uf2')) {
        return FirmwareRelease(board: board, version: tag, fileName: name, url: _checked(Uri.parse(url)));
      }
    }
    throw FirmwareException(FirmwareError.notFound, host: _badgerReleases.host);
  }

  /// Télécharge [release] ; renvoie son nom et son contenu.
  Future<({String name, Uint8List bytes})> download(
    FirmwareRelease release, {
    void Function(int done, int? total)? onProgress,
  }) async {
    final bytes = await _source.fetchBytes(_checked(release.url), onProgress: onProgress);
    return (name: release.fileName, bytes: bytes);
  }

  Uri _checked(Uri url) {
    if (url.scheme != 'https' || !trustedHosts.contains(url.host)) {
      throw FirmwareException(FirmwareError.untrustedSource, host: url.host);
    }
    return url;
  }
}
