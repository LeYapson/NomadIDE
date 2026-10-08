import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:nomad_mcu/app/settings.dart';

/// Langue imposée dans les tests, sans lire ni écrire les réglages.
class FixedLocale extends LocaleController {
  FixedLocale(this.locale);

  final Locale? locale;

  @override
  Locale? build() => locale;

  @override
  Future<void> setLocale(Locale? locale) async => state = locale;
}

Override fixedLocale(String? languageCode) =>
    localeProvider.overrideWith(() => FixedLocale(languageCode == null ? null : Locale(languageCode)));

/// Les tests existants vérifient des textes français.
final Override frenchLocale = fixedLocale('fr');
