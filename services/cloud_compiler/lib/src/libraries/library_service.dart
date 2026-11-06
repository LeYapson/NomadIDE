import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'builtin_headers.dart';
import 'library_cache.dart';
import 'library_index.dart';

/// Renvoie le texte JSON de l'index officiel (déjà décompressé).
typedef IndexFetcher = Future<String> Function();

/// Catalogue des bibliothèques du service : l'index en mémoire, tenu à jour, et le cache d'installation.
class LibraryService {
  LibraryService({
    required this.indexFile,
    required this.fetch,
    required this.cache,
    this.builtin = BuiltinCatalog.empty,
    this.maxAge = const Duration(hours: 24),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final File indexFile;
  final IndexFetcher fetch;
  final LibraryCache cache;
  final Duration maxAge;
  final DateTime Function() _now;

  /// Ce que les cœurs de cartes fournissent déjà ; rempli après le démarrage.
  BuiltinCatalog builtin;

  LibraryIndex? _index;
  DateTime? _updatedAt;
  Timer? _timer;
  Future<void>? _refreshing;

  /// L'index, ou null tant qu'il n'a jamais pu être chargé (ni du disque ni d'Arduino).
  LibraryIndex? get index => _index;

  /// Charge l'index gardé sur le disque (le service répond tout de suite), puis le rafraîchit s'il est absent
  /// ou périmé. Un échec de téléchargement n'empêche pas de servir l'ancien index.
  Future<void> start() async {
    if (indexFile.existsSync()) {
      try {
        _index = LibraryIndex.parse(await indexFile.readAsString());
        _updatedAt = indexFile.lastModifiedSync();
      } on Object {
        // fichier abîmé : on le retélécharge
      }
    }
    if (_index == null || _isStale) await refresh().catchError((_) {});
    _timer = Timer.periodic(const Duration(hours: 1), (_) {
      if (_isStale) refresh().catchError((_) {});
    });
  }

  bool get _isStale => _updatedAt == null || _now().difference(_updatedAt!) > maxAge;

  /// Télécharge l'index et le remplace s'il est lisible. Plusieurs appels simultanés n'en font qu'un.
  Future<void> refresh() => _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<void> _refresh() async {
    final text = await fetch();
    final parsed = LibraryIndex.parse(text);
    if (parsed.libraryCount == 0) throw const FormatException('Index de bibliothèques vide.');
    indexFile.parent.createSync(recursive: true);
    final temp = File('${indexFile.path}.tmp');
    await temp.writeAsString(text);
    await temp.rename(indexFile.path);
    _index = parsed;
    _updatedAt = _now();
  }

  void dispose() => _timer?.cancel();
}

/// Télécharge l'index officiel (`library_index.json.gz`) et le décompresse.
IndexFetcher httpIndexFetcher(Uri url, {Duration timeout = const Duration(minutes: 2), int maxBytes = 120 * 1024 * 1024}) {
  return () async {
    final bytes = await _httpGet(url, allowedHosts: {url.host}, timeout: timeout, maxBytes: maxBytes);
    final raw = url.path.endsWith('.gz') ? gzip.decode(bytes) : bytes;
    return utf8.decode(raw);
  };
}

/// Téléchargeur des archives de bibliothèques : HTTPS seulement, redirections suivies à la main et
/// refusées si elles quittent les hôtes autorisés.
LibraryDownloader httpLibraryDownloader({Set<String> allowedHosts = const {'downloads.arduino.cc'}, Duration timeout = const Duration(minutes: 2)}) {
  return (url, {required maxBytes}) => _httpGet(url, allowedHosts: allowedHosts, timeout: timeout, maxBytes: maxBytes);
}

Future<Uint8List> _httpGet(Uri url, {required Set<String> allowedHosts, required Duration timeout, required int maxBytes}) async {
  final client = HttpClient()
    ..connectionTimeout = timeout
    ..userAgent = 'NomadIDE-compiler';
  try {
    var current = url;
    for (var hop = 0; hop < 4; hop++) {
      if (current.scheme != 'https' || !allowedHosts.contains(current.host)) {
        throw LibraryInstallException('Adresse refusée : ${current.host}.');
      }
      final request = await client.getUrl(current).timeout(timeout);
      request.followRedirects = false;
      final response = await request.close().timeout(timeout);
      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null) throw LibraryInstallException('Redirection invalide.');
        current = current.resolve(location);
        continue;
      }
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw LibraryInstallException('Réponse ${response.statusCode} de ${current.host}.');
      }
      final out = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        out.add(chunk);
        if (out.length > maxBytes) throw LibraryInstallException('Téléchargement trop volumineux.');
      }
      return out.takeBytes();
    }
    throw LibraryInstallException('Trop de redirections.');
  } finally {
    client.close(force: true);
  }
}

/// Fichier de l'index dans le dossier de travail du service.
File defaultIndexFile(String workDir) => File(p.join(workDir, 'library_index.json'));
