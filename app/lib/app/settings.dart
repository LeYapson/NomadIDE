import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../features/projects/data/file_utils.dart';
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

/// Choix de la langue, mémorisé dans `settings.json` à côté des projets.
class LocaleController extends Notifier<Locale?> {
  @override
  Locale? build() {
    Future.microtask(_load);
    return null;
  }

  Future<File> _file() async => File(p.join((await ref.read(storageRootProvider.future)).path, 'settings.json'));

  Future<void> _load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString());
      final code = json is Map ? json['locale'] : null;
      if (ref.mounted && (code == 'fr' || code == 'en')) state = Locale(code as String);
    } catch (_) {
      // Réglages absents ou illisibles : on suit la langue du système.
    }
  }

  /// Change la langue (null : celle du système) et la mémorise.
  Future<void> setLocale(Locale? locale) async {
    state = locale;
    try {
      await atomicWrite(await _file(), utf8.encode(jsonEncode({'locale': locale?.languageCode})));
    } catch (_) {
      // Pas de stockage : le choix vaut pour cette session seulement.
    }
  }
}
