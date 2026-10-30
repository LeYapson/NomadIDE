import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings.dart';
import '../../../l10n/l10n.dart';

/// Réglages de l'application : langue de l'interface.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final chosen = ref.watch(localeProvider)?.languageCode;
    void choose(String? code) => ref.read(localeProvider.notifier).setLocale(code == null ? null : Locale(code));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: SafeArea(
        child: ListView(
          children: [
            ListTile(title: Text(l10n.settingsLanguage), textColor: Theme.of(context).colorScheme.primary),
            _ChoiceTile(label: l10n.languageSystem, selected: chosen == null, onTap: () => choose(null)),
            _ChoiceTile(label: l10n.languageFrench, selected: chosen == 'fr', onTap: () => choose('fr')),
            _ChoiceTile(label: l10n.languageEnglish, selected: chosen == 'en', onTap: () => choose('en')),
          ],
        ),
      ),
    );
  }
}

/// Un choix parmi plusieurs : toute la ligne (au moins 56 dp) est la zone tactile, et le lecteur d'écran
/// l'annonce comme un choix exclusif, coché ou non. Remplace `RadioListTile`, dont le bouton radio
/// interne forme une seconde zone tactile de 40 dp sans nom.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: ListTile(
        onTap: onTap,
        selected: selected,
        leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, color: selected ? scheme.primary : scheme.onSurfaceVariant),
        title: Text(label),
      ),
    );
  }
}
