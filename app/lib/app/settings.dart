import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../features/projects/data/file_utils.dart';
import '../features/serial_monitor/application/serial_monitor_state.dart' show LineEnding;
import '../l10n/l10n.dart';
import 'providers.dart';

/// Langue choisie par l'utilisateur ; null = suivre la langue du système.
final localeProvider = NotifierProvider<LocaleController, Locale?>(LocaleController.new);

/// Textes dans la langue effective, pour le code qui n'a pas de `BuildContext`
/// (messages des contrôleurs, journal de la carte).
final l10nProvider = Provider<AppLocalizations>((ref) {
  final chosen = ref.watch(localeProvider);
  return lookupAppLocalizations(resolveAppLocale(chosen, PlatformDispatcher.instance.locale));
});

/// Le fichier `settings.json` de l'application, partagé par la langue et les autres réglages.
final settingsFileProvider = Provider<SettingsFile>(SettingsFile.new);

/// Le fichier `settings.json`, à côté des projets. Chaque réglage n'écrit que sa clé : les écritures
/// sont mises en file pour qu'aucune n'efface celle d'un autre réglage.
class SettingsFile {
  SettingsFile(this._ref);

  final Ref _ref;
  Future<void> _queue = Future.value();

  Future<File> _file() async => File(p.join((await _ref.read(storageRootProvider.future)).path, 'settings.json'));

  /// Contenu du fichier ; vide s'il est absent ou illisible.
  Future<Map<String, Object?>> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return {};
      final json = jsonDecode(await file.readAsString());
      return json is Map<String, Object?> ? json : {};
    } catch (_) {
      return {};
    }
  }

  /// Remplace les clés de [changes] et garde les autres.
  Future<void> update(Map<String, Object?> changes) {
    final done = _queue.then((_) async {
      final current = await read();
      await atomicWrite(await _file(), utf8.encode(jsonEncode({...current, ...changes})));
    });
    _queue = done.catchError((_) {});
    return done;
  }
}

/// Choix de la langue, mémorisé dans `settings.json`.
class LocaleController extends Notifier<Locale?> {
  @override
  Locale? build() {
    Future.microtask(_load);
    return null;
  }

  Future<void> _load() async {
    final code = (await ref.read(settingsFileProvider).read())['locale'];
    if (ref.mounted && (code == 'fr' || code == 'en')) state = Locale(code as String);
  }

  /// Change la langue (null : celle du système) et la mémorise.
  Future<void> setLocale(Locale? locale) async {
    state = locale;
    try {
      await ref.read(settingsFileProvider).update({'locale': locale?.languageCode});
    } catch (_) {
      // Pas de stockage : le choix vaut pour cette session seulement.
    }
  }
}

/// Réglages de l'application autres que la langue.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.editorFontSize = defaultEditorFontSize,
    this.editorWordWrap = false,
    this.monitorBaud = 115200,
    this.monitorLineEnding = LineEnding.cr,
    this.monitorTimestamps = true,
    this.onboardingDone = false,
    this.checkUpdates = true,
    this.loaded = false,
  });

  static const double defaultEditorFontSize = 14;
  static const double minEditorFontSize = 10;
  static const double maxEditorFontSize = 28;

  final ThemeMode themeMode;
  final double editorFontSize;
  final bool editorWordWrap;

  /// Valeurs par défaut du moniteur série à l'ouverture de l'app.
  final int monitorBaud;
  final LineEnding monitorLineEnding;
  final bool monitorTimestamps;

  /// Le tutoriel de prise en main a été suivi (ou passé).
  final bool onboardingDone;

  /// Chercher au démarrage une version plus récente sur GitHub.
  final bool checkUpdates;

  /// Le fichier a été lu (même absent) : avant, les valeurs ne sont que celles par défaut. Évite par
  /// exemple d'afficher le tutoriel une fraction de seconde à quelqu'un qui l'a déjà vu.
  final bool loaded;

  factory AppSettings.fromJson(Map<String, Object?> json) {
    const d = AppSettings();
    T pick<T>(String key, T fallback, bool Function(T value) valid) {
      final value = json[key];
      return value is T && valid(value) ? value : fallback;
    }

    return AppSettings(
      themeMode: ThemeMode.values.where((m) => m.name == json['theme']).firstOrNull ?? d.themeMode,
      editorFontSize: pick<num>('editorFontSize', d.editorFontSize, (v) => v >= minEditorFontSize && v <= maxEditorFontSize).toDouble(),
      editorWordWrap: pick<bool>('editorWordWrap', d.editorWordWrap, (_) => true),
      monitorBaud: pick<int>('monitorBaud', d.monitorBaud, (v) => v > 0),
      monitorLineEnding: LineEnding.values.where((e) => e.name == json['monitorLineEnding']).firstOrNull ?? d.monitorLineEnding,
      monitorTimestamps: pick<bool>('monitorTimestamps', d.monitorTimestamps, (_) => true),
      onboardingDone: pick<bool>('onboardingDone', d.onboardingDone, (_) => true),
      checkUpdates: pick<bool>('checkUpdates', d.checkUpdates, (_) => true),
      loaded: true,
    );
  }

  AppSettings copyWith({
    ThemeMode? themeMode,
    double? editorFontSize,
    bool? editorWordWrap,
    int? monitorBaud,
    LineEnding? monitorLineEnding,
    bool? monitorTimestamps,
    bool? onboardingDone,
    bool? checkUpdates,
    bool? loaded,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        editorFontSize: editorFontSize ?? this.editorFontSize,
        editorWordWrap: editorWordWrap ?? this.editorWordWrap,
        monitorBaud: monitorBaud ?? this.monitorBaud,
        monitorLineEnding: monitorLineEnding ?? this.monitorLineEnding,
        monitorTimestamps: monitorTimestamps ?? this.monitorTimestamps,
        onboardingDone: onboardingDone ?? this.onboardingDone,
        checkUpdates: checkUpdates ?? this.checkUpdates,
        loaded: loaded ?? this.loaded,
      );
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// Réglages mémorisés dans `settings.json` ; valeurs par défaut tant que le fichier n'est pas lu.
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    Future.microtask(_load);
    return const AppSettings();
  }

  /// Vrai dès qu'un réglage a été changé dans la session.
  bool _changed = false;

  Future<void> _load() async {
    final json = await ref.read(settingsFileProvider).read();
    if (!ref.mounted) return;
    // Un réglage changé pendant la lecture du fichier l'emporte : on ne l'écrase pas par l'ancienne valeur.
    state = _changed ? state.copyWith(loaded: true) : AppSettings.fromJson(json);
  }

  Future<void> _save(AppSettings next, String key, Object? value) async {
    _changed = true;
    state = next;
    try {
      await ref.read(settingsFileProvider).update({key: value});
    } catch (_) {
      // Pas de stockage : le réglage vaut pour cette session seulement.
    }
  }

  Future<void> setThemeMode(ThemeMode mode) => _save(state.copyWith(themeMode: mode), 'theme', mode.name);

  Future<void> setEditorFontSize(double size) {
    final clamped = size.clamp(AppSettings.minEditorFontSize, AppSettings.maxEditorFontSize).roundToDouble();
    return _save(state.copyWith(editorFontSize: clamped), 'editorFontSize', clamped);
  }

  Future<void> setEditorWordWrap(bool wrap) => _save(state.copyWith(editorWordWrap: wrap), 'editorWordWrap', wrap);

  Future<void> setMonitorBaud(int baud) => _save(state.copyWith(monitorBaud: baud), 'monitorBaud', baud);

  Future<void> setMonitorLineEnding(LineEnding ending) =>
      _save(state.copyWith(monitorLineEnding: ending), 'monitorLineEnding', ending.name);

  Future<void> setMonitorTimestamps(bool on) => _save(state.copyWith(monitorTimestamps: on), 'monitorTimestamps', on);

  Future<void> setOnboardingDone(bool done) => _save(state.copyWith(onboardingDone: done), 'onboardingDone', done);

  Future<void> setCheckUpdates(bool on) => _save(state.copyWith(checkUpdates: on), 'checkUpdates', on);
}
