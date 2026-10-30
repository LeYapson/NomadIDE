import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:package_info_plus/package_info_plus.dart';

import '../../../app/providers.dart';
import '../../../app/settings.dart';
import '../../flash/application/esp_flash_controller.dart';
import '../../flash/application/flash_controller.dart';
import '../../micropython/application/micropython_controller.dart';
import '../../serial_monitor/application/serial_monitor_controller.dart';
import '../../serial_monitor/domain/log_entry.dart';

/// Lecture d'un provider : `ref.read` d'un contrôleur comme d'un widget.
typedef Reader = T Function<T>(ProviderListenable<T> provider);

/// Adresse du dépôt, pour « À propos » et les rapports de bug.
const String repositoryUrl = 'https://github.com/LeYapson/NomadIDE';

/// Version de l'app (« 0.1.0 (1) ») ; « ? » si la plateforme ne la donne pas.
final appVersionProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return '${info.version} (${info.buildNumber})';
  } catch (_) {
    return '?';
  }
});

/// Dossier du cache des bibliothèques MicroPython (voir `mipClientProvider`).
Future<Directory> libraryCacheDirectory(Reader read) async =>
    Directory('${(await read(storageRootProvider.future)).path}/cache/mip');

/// Taille totale des fichiers de [dir] (0 s'il n'existe pas).
Future<int> directorySize(Directory dir) async {
  if (!await dir.exists()) return 0;
  var total = 0;
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File) total += await entity.length();
  }
  return total;
}

/// Nombre de lignes de journal reprises de chaque source.
const int _logLines = 60;

/// Rapport de diagnostic à joindre à un signalement de bug : versions, plateforme, réglages, cartes
/// détectées et derniers messages système et erreurs. Il ne contient **ni le code des projets ni le flux
/// série** (données reçues ou envoyées), seulement ce que l'app a elle-même affiché comme état ou erreur.
Future<String> buildDiagnosticReport(Reader read, {DateTime? now}) async {
  final out = StringBuffer();
  void line([String text = '']) => out.writeln(text);
  void section(String title) {
    line();
    line('## $title');
  }

  final settings = read(settingsProvider);
  line('# Diagnostic NomadIDE');
  line('Date : ${(now ?? DateTime.now()).toIso8601String()}');
  line('Version : ${await read(appVersionProvider.future)}');
  line('Système : ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  line('Dart : ${Platform.version.split(' ').first}');
  line('Langue : ${read(localeProvider)?.languageCode ?? 'système (${Platform.localeName})'}');

  section('Réglages');
  line('Thème : ${settings.themeMode.name}');
  line('Éditeur : ${settings.editorFontSize.round()} pt, retour à la ligne ${settings.editorWordWrap ? 'oui' : 'non'}');
  line('Moniteur : ${settings.monitorBaud} bauds, fin de ligne ${settings.monitorLineEnding.name}, horodatage ${settings.monitorTimestamps ? 'oui' : 'non'}');

  section('Cartes détectées');
  final transport = read(serialTransportProvider);
  line('Transport : ${transport.kind.name}');
  try {
    final devices = await transport.listDevices();
    if (devices.isEmpty) line('(aucune)');
    for (final d in devices) {
      String hex(int? v) => v == null ? '----' : v.toRadixString(16).padLeft(4, '0').toUpperCase();
      line('- ${d.displayName} · ${hex(d.vendorId)}:${hex(d.productId)} · ${d.chip.label} · ${d.systemPath}');
    }
  } catch (e) {
    line('(énumération impossible : $e)');
  }

  section('Moniteur série (état et erreurs)');
  final monitor = read(serialMonitorProvider);
  line('État : ${monitor.status.name}');
  for (final e in monitor.entries.where((e) => e.kind == LogKind.system || e.kind == LogKind.error).toList().reversed.take(_logLines).toList().reversed) {
    line('${e.kind == LogKind.error ? '✖' : '•'} ${utf8.decode(e.bytes, allowMalformed: true).trim()}');
  }

  section('MicroPython (état et erreurs)');
  final micro = read(microPythonProvider);
  line('État : ${micro.status.name}');
  for (final e in micro.log.where((e) => e.kind == ReplLogKind.info || e.kind == ReplLogKind.err).toList().reversed.take(_logLines).toList().reversed) {
    line('${e.kind == ReplLogKind.err ? '✖' : '•'} ${e.text.trim()}');
  }

  section('Flash');
  final uf2 = read(flashProvider);
  line('UF2 : ${uf2.phase.name}${uf2.message == null ? '' : ' — ${uf2.message}'}');
  final esp = read(espFlashProvider);
  line('ESP : ${esp.phase.name}${esp.message == null ? '' : ' — ${esp.message}'}');

  return out.toString();
}

/// Écrit [report] dans `diagnostics/` à côté des projets et renvoie le fichier.
Future<File> saveDiagnosticReport(Reader read, String report, {DateTime? now}) async {
  final t = now ?? DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  final name = 'nomadide-diagnostic-${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}.txt';
  final dir = Directory('${(await read(storageRootProvider.future)).path}/diagnostics');
  await dir.create(recursive: true);
  final file = File('${dir.path}/$name');
  await file.writeAsString(report);
  return file;
}
