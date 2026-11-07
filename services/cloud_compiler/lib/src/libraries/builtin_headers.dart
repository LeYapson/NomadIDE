import 'dart:io';

import 'package:nomad_compile_api/nomad_compile_api.dart';

import '../config.dart';

/// Ce que le cœur d'une carte fournit déjà : ses bibliothèques (`Wire`, `SPI`, `WiFi`…) et leurs en-têtes
/// (`Wire.h`), ainsi que les en-têtes du cœur lui-même (`Arduino.h`). Inutile de les chercher dans l'index.
class BuiltinInfo {
  const BuiltinInfo({this.libraries = const {}, this.headers = const {}});

  final Set<String> libraries;
  final Set<String> headers;

  static const BuiltinInfo empty = BuiltinInfo();

  bool providesHeader(String header) => headers.contains(header);

  BuiltinInfo merge(BuiltinInfo other) =>
      BuiltinInfo(libraries: {...libraries, ...other.libraries}, headers: {...headers, ...other.headers});
}

/// Les cœurs installés dans l'image, par famille de carte.
class BuiltinCatalog {
  const BuiltinCatalog(this._byFamily);

  final Map<CompileFamily, BuiltinInfo> _byFamily;

  static const BuiltinCatalog empty = BuiltinCatalog({});

  BuiltinInfo forFamily(CompileFamily family) => _byFamily[family] ?? BuiltinInfo.empty;

  /// Analyse la sortie de la commande de [DockerBuiltinLoader] : un chemin par ligne, de la forme
  /// `…/packages/<paquet>/hardware/<arch>/<version>/{libraries|cores}/…`. Un dossier de bibliothèque finit par
  /// `/libraries/<Nom>`, un en-tête par `.h`.
  factory BuiltinCatalog.parse(String output) {
    final libraries = <CompileFamily, Set<String>>{};
    final headers = <CompileFamily, Set<String>>{};
    final pattern = RegExp(r'packages/([^/]+)/hardware/[^/]+/[^/]+/(libraries|cores)/(.+)$');
    for (final raw in output.split('\n')) {
      final match = pattern.firstMatch(raw.trim());
      if (match == null) continue;
      final family = switch (match.group(1)) {
        'esp32' => CompileFamily.esp,
        'rp2040' => CompileFamily.rp2040,
        _ => null,
      };
      if (family == null) continue;
      final rest = match.group(3)!.split('/');
      if (match.group(2) == 'libraries') {
        libraries.putIfAbsent(family, () => {}).add(rest.first);
      }
      final last = rest.last;
      if (last.endsWith('.h') || last.endsWith('.hpp')) headers.putIfAbsent(family, () => {}).add(last);
    }
    return BuiltinCatalog({
      for (final family in {...libraries.keys, ...headers.keys})
        family: BuiltinInfo(libraries: libraries[family] ?? {}, headers: headers[family] ?? {}),
    });
  }
}

/// Interroge l'image de compilation (sans réseau) pour lister les bibliothèques et en-têtes des cœurs.
class DockerBuiltinLoader {
  DockerBuiltinLoader(this.config);

  final ServerConfig config;

  Future<BuiltinCatalog> load() async {
    final result = await Process.run(config.dockerBinary, [
      'run',
      '--rm',
      '--network',
      'none',
      '--read-only',
      '--cap-drop',
      'ALL',
      config.dockerImage,
      'find',
      '/opt/arduino/data/packages',
      '(',
      '-type',
      'd',
      '-path',
      '*/hardware/*/*/libraries/*',
      '-o',
      '-name',
      '*.h',
      '-path',
      '*/hardware/*/*/libraries/*',
      '-o',
      '-name',
      '*.h',
      '-path',
      '*/hardware/*/*/cores/*',
      ')',
      '-print',
    ]);
    if (result.exitCode != 0) return BuiltinCatalog.empty;
    return BuiltinCatalog.parse(result.stdout as String);
  }
}

/// Même liste, lue directement dans le dossier `packages` d'`arduino-cli` (compilation locale, sans Docker).
class DirectoryBuiltinLoader {
  DirectoryBuiltinLoader(this.packagesDir);

  final Directory packagesDir;

  Future<BuiltinCatalog> load() async {
    if (!packagesDir.existsSync()) return BuiltinCatalog.empty;
    final lines = StringBuffer();
    // packages/<paquet>/hardware/<arch>/<version>/{libraries|cores}
    for (final package in packagesDir.listSync().whereType<Directory>()) {
      final hardware = Directory('${package.path}/hardware');
      if (!hardware.existsSync()) continue;
      for (final arch in hardware.listSync().whereType<Directory>()) {
        for (final version in arch.listSync().whereType<Directory>()) {
          for (final kind in const ['libraries', 'cores']) {
            final root = Directory('${version.path}/$kind');
            if (!root.existsSync()) continue;
            await for (final entity in root.list(recursive: true, followLinks: false)) {
              final path = entity.path.replaceAll('\\', '/');
              if (entity is Directory && kind == 'libraries' && entity.parent.path == root.path || path.endsWith('.h') || path.endsWith('.hpp')) {
                lines.writeln(path);
              }
            }
          }
        }
      }
    }
    return BuiltinCatalog.parse(lines.toString());
  }
}
