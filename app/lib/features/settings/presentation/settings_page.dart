
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
    final chosen = ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: SafeArea(
        child: ListView(
          children: [
            ListTile(title: Text(l10n.settingsLanguage), textColor: Theme.of(context).colorScheme.primary),
            RadioGroup<String?>(
              groupValue: chosen?.languageCode,
              onChanged: (code) => ref.read(localeProvider.notifier).setLocale(code == null ? null : Locale(code)),
              child: Column(
                children: [
                  RadioListTile<String?>(value: null, title: Text(l10n.languageSystem)),
                  RadioListTile<String?>(value: 'fr', title: Text(l10n.languageFrench)),
                  RadioListTile<String?>(value: 'en', title: Text(l10n.languageEnglish)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
