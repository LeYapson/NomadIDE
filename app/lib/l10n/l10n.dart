
import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart';

/// Langues de l'interface. Le français est la langue source ; l'anglais est utilisé
/// pour toute autre langue du système.
const List<Locale> appLocales = [Locale('en'), Locale('fr')];

/// Locale effective : le choix de l'utilisateur, sinon la langue du système (français
/// ou anglais par défaut).
Locale resolveAppLocale(Locale? chosen, Locale system) {
  final language = (chosen ?? system).languageCode;
  return Locale(language == 'fr' ? 'fr' : 'en');
}

extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
