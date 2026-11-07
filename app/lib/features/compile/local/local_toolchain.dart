import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Version d'`arduino-cli` installée pour la compilation locale. Figée : les compilations ne changent pas
/// de comportement sans qu'une version de l'app le décide.
const String arduinoCliVersion = '1.5.1';

const List<String> boardManagerUrls = [
  'https://espressif.github.io/arduino-esp32/package_esp32_index.json',
  'https://github.com/earlephilhower/arduino-pico/releases/download/global/package_rp2040_index.json',
];

/// Cœurs installés pour les cartes de la v1 (voir `CompileBoard`).
const List<String> toolchainCores = ['esp32:esp32', 'rp2040:rp2040'];

/// Ordre de grandeur de ce qui est téléchargé, annoncé avant l'installation.
const int toolchainApproxDownloadMb = 1100;

enum ToolchainStep { downloadCli, updateIndex, installCore, done }

class ToolchainProgress {
  const ToolchainProgress(this.step, {this.core, this.line});

  final ToolchainStep step;

  /// Cœur en cours d'installation (`esp32:esp32`).
  final String? core;

  /// Dernière ligne affichée par l'outil, pour montrer que ça avance.
  final String? line;
}

class ToolchainException implements Exception {
  const ToolchainException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Télécharge une adresse HTTPS et renvoie son contenu ; remplaçable dans les tests.
typedef Downloader = Future<Uint8List> Function(Uri url, {required int maxBytes, void Function(int received)? onProgress});

Future<Uint8List> httpDownloader(Uri url, {required int maxBytes, void Function(int received)? onProgress}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final request = await client.getUrl(url);
    request.headers.set(HttpHeaders.userAgentHeader, 'NomadIDE');
    final response = await request.close();
    if (response.statusCode != 200) throw ToolchainException('HTTP ${response.statusCode} pour ${url.host}');
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
      onProgress?.call(bytes.length);
      if (bytes.length > maxBytes) throw const ToolchainException('Fichier trop volumineux.');
    }
    return bytes.takeBytes();
  } on ToolchainException {
    rethrow;
  } on Object catch (e) {
    throw ToolchainException('Téléchargement impossible : $e');
  } finally {
    client.close(force: true);
  }
}

/// Nom de l'archive d'`arduino-cli` pour cet ordinateur, ou null si on n'en publie pas.
String? arduinoCliArchiveName({required String os, required String arch, String version = arduinoCliVersion}) {
  final target = switch ((os, arch)) {
    ('windows', 'x64') => 'Windows_64bit.zip',
    ('linux', 'x64') => 'Linux_64bit.tar.gz',
    ('linux', 'arm64') => 'Linux_ARM64.tar.gz',
    ('macos', 'x64') => 'macOS_64bit.tar.gz',
    ('macos', 'arm64') => 'macOS_ARM64.tar.gz',
    _ => null,
  };
  return target == null ? null : 'arduino-cli_${version}_$target';
}

/// Ligne `<sha256>  <fichier>` du fichier d'empreintes d'une version.
String? checksumFor(String checksums, String fileName) {
  for (final line in const LineSplitter().convert(checksums)) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length == 2 && parts[1].replaceFirst('*', '') == fileName) return parts[0].toLowerCase();
  }
  return null;
}

/// `arduino-cli` et ses cœurs, installés dans un dossier de l'app (rien n'est écrit ailleurs).
///
/// Tout est confiné à [root] par des variables d'environnement : l'installation d'Arduino IDE de l'utilisateur,
/// s'il en a une, n'est ni lue ni modifiée.
class LocalToolchain {
  LocalToolchain(this.root, {Downloader? download, String? os, String? arch})
      : _download = download ?? httpDownloader,
        _os = os ?? _hostOs(),
        _arch = arch ?? _hostArch();

  final Directory root;
  final Downloader _download;
  final String _os;
  final String _arch;

  static String _hostOs() => Platform.isWindows ? 'windows' : (Platform.isMacOS ? 'macos' : 'linux');

  static String _hostArch() {
    // Dart ne donne pas l'architecture directement : `version` finit par « "os_arch" ».
    final version = Platform.version;
    if (version.contains('arm64') || version.contains('aarch64')) return 'arm64';
    return 'x64';
  }

  /// Vrai si une archive officielle existe pour cet ordinateur.
  bool get supported => arduinoCliArchiveName(os: _os, arch: _arch) != null;

  File get cli => File(p.join(root.path, 'bin', _os == 'windows' ? 'arduino-cli.exe' : 'arduino-cli'));
  Directory get dataDir => Directory(p.join(root.path, 'data'));
  Directory get userDir => Directory(p.join(root.path, 'user'));
  Directory get downloadsDir => Directory(p.join(root.path, 'staging'));
  Directory get packagesDir => Directory(p.join(dataDir.path, 'packages'));

  /// Variables d'environnement d'`arduino-cli` : tout reste dans [root].
  Map<String, String> get environment => {
        'ARDUINO_DIRECTORIES_DATA': dataDir.path,
        'ARDUINO_DIRECTORIES_USER': userDir.path,
        'ARDUINO_DIRECTORIES_DOWNLOADS': downloadsDir.path,
        // Cache des cœurs déjà compilés : la deuxième compilation est bien plus rapide.
        'ARDUINO_BUILD_CACHE_PATH': p.join(root.path, 'cache'),
        'ARDUINO_UPDATER_ENABLE_NOTIFICATION': 'false',
        'ARDUINO_BOARD_MANAGER_ADDITIONAL_URLS': boardManagerUrls.join(','),
      };

  bool get cliInstalled => cli.existsSync();

  /// Un cœur (`esp32:esp32`) est installé s'il a au moins une version dans `data/packages/<paquet>/hardware/<arch>/`.
  bool coreInstalled(String core) {
    final parts = core.split(':');
    final hardware = Directory(p.join(packagesDir.path, parts[0], 'hardware', parts[1]));
    return hardware.existsSync() && hardware.listSync().whereType<Directory>().isNotEmpty;
  }

  List<String> get missingCores => [for (final core in toolchainCores) if (!coreInstalled(core)) core];

  bool get ready => cliInstalled && missingCores.isEmpty;

  /// Installe ce qui manque. Chaque étape déjà faite est sautée : relancer après une coupure reprend là où on s'était arrêté.
  Stream<ToolchainProgress> install({CancelSignal? cancel}) async* {
    final signal = cancel ?? CancelSignal();
    if (!supported) throw const ToolchainException('Aucune version officielle d\'arduino-cli pour cet ordinateur.');
    await root.create(recursive: true);

    if (!cliInstalled) {
      yield const ToolchainProgress(ToolchainStep.downloadCli);
      await _installCli();
    }
    if (missingCores.isNotEmpty) {
      yield const ToolchainProgress(ToolchainStep.updateIndex);
      await _run(['core', 'update-index', '--additional-urls', boardManagerUrls.join(',')], signal).drain<void>();
      for (final core in missingCores) {
        await for (final line in _run(['core', 'install', core, '--additional-urls', boardManagerUrls.join(',')], signal)) {
          yield ToolchainProgress(ToolchainStep.installCore, core: core, line: line);
        }
        if (!coreInstalled(core)) throw ToolchainException('Le cœur $core ne s\'est pas installé.');
      }
    }
    yield const ToolchainProgress(ToolchainStep.done);
  }

  Future<void> _installCli() async {
    final name = arduinoCliArchiveName(os: _os, arch: _arch)!;
    final base = Uri.parse('https://github.com/arduino/arduino-cli/releases/download/v$arduinoCliVersion/');
    final checksums = utf8.decode(await _download(base.resolve('$arduinoCliVersion-checksums.txt'), maxBytes: 1024 * 1024));
    final expected = checksumFor(checksums, name);
    if (expected == null) throw ToolchainException('Empreinte introuvable pour $name.');
    final bytes = await _download(base.resolve(name), maxBytes: 200 * 1024 * 1024);
    if (sha256.convert(bytes).toString() != expected) {
      throw const ToolchainException('L\'empreinte d\'arduino-cli ne correspond pas : téléchargement refusé.');
    }
    final Archive archive = name.endsWith('.zip')
        ? ZipDecoder().decodeBytes(bytes)
        : TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
    final wanted = _os == 'windows' ? 'arduino-cli.exe' : 'arduino-cli';
    final entry = archive.files.where((f) => f.isFile && f.name == wanted).firstOrNull;
    if (entry == null) throw const ToolchainException('L\'archive d\'arduino-cli est inattendue.');
    await cli.parent.create(recursive: true);
    // Écrit sous un autre nom puis renommé : une coupure ne laisse pas un exécutable tronqué.
    final partial = File('${cli.path}.part');
    await partial.writeAsBytes(entry.content, flush: true);
    if (_os != 'windows') await Process.run('chmod', ['755', partial.path]);
    await partial.rename(cli.path);
  }

  /// Lance `arduino-cli` et donne ses lignes de sortie ; une sortie en erreur lève [ToolchainException].
  Stream<String> _run(List<String> args, CancelSignal cancel) async* {
    final Process process;
    try {
      process = await Process.start(cli.path, args, environment: environment, includeParentEnvironment: true);
    } on ProcessException catch (e) {
      throw ToolchainException('arduino-cli ne démarre pas : ${e.message}');
    }
    cancel.onCancel(() => killProcessTree(process));
    final lines = StreamController<String>();
    var open = 2;
    void done() {
      if (--open == 0) lines.close();
    }

    final tail = <String>[];
    void feed(Stream<List<int>> stream) => stream.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
          final text = line.trim();
          if (text.isEmpty) return;
          tail.add(text);
          if (tail.length > 8) tail.removeAt(0);
          lines.add(text);
        }, onDone: done);
    feed(process.stdout);
    feed(process.stderr);
    yield* lines.stream;
    final code = await process.exitCode;
    if (cancel.cancelled) throw const ToolchainException('Installation annulée.');
    if (code != 0) throw ToolchainException('arduino-cli a échoué (code $code) : ${tail.join(' / ')}');
  }

  /// Supprime tout (le bouton « Désinstaller » des réglages).
  Future<void> uninstall() async {
    if (root.existsSync()) await root.delete(recursive: true);
  }
}

/// Annulation partagée entre l'écran et les processus lancés.
class CancelSignal {
  bool cancelled = false;
  final List<void Function()> _listeners = [];

  void onCancel(void Function() listener) {
    if (cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void cancel() {
    if (cancelled) return;
    cancelled = true;
    for (final l in _listeners) {
      l();
    }
  }
}

/// Arrête le processus et ses enfants : sur Windows, `Process.kill` laisserait tourner gcc.
void killProcessTree(Process process) {
  if (Platform.isWindows) {
    Process.run('taskkill', ['/T', '/F', '/PID', '${process.pid}']);
  } else {
    process.kill();
  }
}
