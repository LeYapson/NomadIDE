import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_hal/nomad_hal.dart' show SerialConfig;

import '../../../app/brand.dart';
import '../../../app/links.dart';
import '../../../app/providers.dart';
import '../../../app/settings.dart';
import '../../../app/theme.dart';
import '../../../l10n/error_messages.dart';
import '../../../l10n/l10n.dart';
import '../../flash/application/flash_controller.dart' show flashSizeLabel;
import '../../onboarding/onboarding_page.dart';
import '../../serial_monitor/application/serial_monitor_state.dart' show LineEnding;
import '../../compile/application/compile_controller.dart' show compileApiProvider;
import '../../compile/data/compile_api.dart';
import '../../compile/presentation/compile_messages.dart';
import '../application/diagnostics.dart';
import '../application/update_checker.dart';

/// Réglages de l'application : langue, apparence, éditeur, moniteur série, aide, données, à propos.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late Future<int> _cacheSize = _readCacheSize();

  Future<int> _readCacheSize() async {
    try {
      return await directorySize(await libraryCacheDirectory(ref.read));
    } catch (_) {
      return 0;
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _snack(context.l10n.settingsCopied);
  }

  Future<void> _open(Uri url) async {
    if (!await openOrCopy(ref, url) && mounted) _snack(context.l10n.linkOpenFailed);
  }

  Future<void> _exportDiagnostic() async {
    final l10n = context.l10n;
    try {
      final report = await buildDiagnosticReport(ref.read);
      await Clipboard.setData(ClipboardData(text: report));
      final file = await saveDiagnosticReport(ref.read, report);
      if (mounted) _snack(l10n.settingsDiagnosticDone(file.path));
    } catch (e) {
      if (mounted) _snack(l10n.settingsDiagnosticFailed(errorMessage(l10n, e)));
    }
  }

  Future<void> _clearCache() async {
    try {
      final dir = await libraryCacheDirectory(ref.read);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Rien à vider, ou fichier verrouillé : la taille affichée le dira.
    }
    if (!mounted) return;
    setState(() => _cacheSize = _readCacheSize());
    _snack(context.l10n.settingsCacheCleared);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final chosen = ref.watch(localeProvider)?.languageCode;
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    void chooseLocale(String? code) => ref.read(localeProvider.notifier).setLocale(code == null ? null : Locale(code));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _SectionHeader(l10n.settingsLanguage),
            _ChoiceTile(label: l10n.languageSystem, selected: chosen == null, onTap: () => chooseLocale(null)),
            _ChoiceTile(label: l10n.languageFrench, selected: chosen == 'fr', onTap: () => chooseLocale('fr')),
            _ChoiceTile(label: l10n.languageEnglish, selected: chosen == 'en', onTap: () => chooseLocale('en')),

            _SectionHeader(l10n.settingsAppearance),
            for (final (mode, label) in [
              (ThemeMode.system, l10n.themeSystem),
              (ThemeMode.light, l10n.themeLight),
              (ThemeMode.dark, l10n.themeDark),
            ])
              _ChoiceTile(label: label, selected: settings.themeMode == mode, onTap: () => controller.setThemeMode(mode)),

            _SectionHeader(l10n.settingsEditor),
            ListTile(
              title: Text(l10n.settingsFontSize(settings.editorFontSize.round())),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Slider(
                    value: settings.editorFontSize,
                    min: AppSettings.minEditorFontSize,
                    max: AppSettings.maxEditorFontSize,
                    divisions: (AppSettings.maxEditorFontSize - AppSettings.minEditorFontSize).round(),
                    label: '${settings.editorFontSize.round()}',
                    semanticFormatterCallback: (v) => l10n.settingsFontSize(v.round()),
                    onChanged: controller.setEditorFontSize,
                  ),
                  // Aperçu : le texte du code tel qu'il sera affiché.
                  ExcludeSemantics(
                    child: Text(
                      'print("NomadIDE")  # 0O 1lI',
                      style: monoTextStyle.copyWith(fontSize: settings.editorFontSize, color: Theme.of(context).colorScheme.onSurface),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            SwitchListTile(
              title: Text(l10n.settingsWordWrap),
              subtitle: Text(l10n.settingsWordWrapHint),
              value: settings.editorWordWrap,
              onChanged: controller.setEditorWordWrap,
            ),

            _SectionHeader(l10n.settingsMonitor),
            _DropdownTile<int>(
              label: l10n.settingsDefaultBaud,
              value: settings.monitorBaud,
              items: {for (final b in SerialConfig.standardBaudRates) b: '$b'},
              onChanged: controller.setMonitorBaud,
            ),
            _DropdownTile<LineEnding>(
              label: l10n.settingsDefaultLineEnding,
              value: settings.monitorLineEnding,
              items: {for (final e in LineEnding.values) e: e == LineEnding.none ? l10n.monLineEndingNone : e.label},
              onChanged: controller.setMonitorLineEnding,
            ),
            SwitchListTile(
              title: Text(l10n.settingsDefaultTimestamps),
              value: settings.monitorTimestamps,
              onChanged: controller.setMonitorTimestamps,
            ),

            _SectionHeader(l10n.settingsCompile),
            const _CompileSettings(),

            _SectionHeader(l10n.settingsHelp),
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: Text(l10n.settingsTutorial),
              subtitle: Text(l10n.settingsTutorialHint),
              onTap: () => showOnboarding(context),
            ),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: Text(l10n.settingsDiagnostic),
              subtitle: Text(l10n.settingsDiagnosticHint),
              onTap: _exportDiagnostic,
            ),

            _SectionHeader(l10n.settingsData),
            ref.watch(storageRootProvider).when(
                  data: (dir) => ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(l10n.settingsProjectsFolder),
                    subtitle: SelectableText(dir.path),
                    trailing: IconButton(
                      tooltip: l10n.settingsCopyPath,
                      onPressed: () => _copy(dir.path),
                      icon: const Icon(Icons.copy),
                    ),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
            FutureBuilder<int>(
              future: _cacheSize,
              builder: (context, snapshot) {
                final size = snapshot.data ?? 0;
                return ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: Text(l10n.settingsClearCache),
                  subtitle: Text(size == 0 ? l10n.settingsCacheEmpty : l10n.settingsCacheSize(flashSizeLabel(l10n, size))),
                  enabled: size > 0,
                  onTap: size > 0 ? _clearCache : null,
                );
              },
            ),

            _SectionHeader(l10n.settingsAbout),
            ListTile(
              leading: const NomadLogo(size: 40),
              title: Text(l10n.settingsVersion),
              subtitle: Text(ref.watch(appVersionProvider).value ?? '…'),
            ),
            _UpdateTile(onOpen: _open),
            SwitchListTile(
              title: Text(l10n.updAuto),
              subtitle: Text(l10n.updAutoHint),
              value: settings.checkUpdates,
              onChanged: controller.setCheckUpdates,
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: Text(l10n.settingsSource),
              subtitle: const Text(repositoryUrl),
              onTap: () => _open(Uri.parse(repositoryUrl)),
              trailing: IconButton(
                tooltip: l10n.settingsCopyPath,
                onPressed: () => _copy(repositoryUrl),
                icon: const Icon(Icons.copy),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(l10n.settingsLicenses),
              subtitle: Text(l10n.settingsLicensesHint),
              onTap: () => showLicensePage(
                context: context,
                applicationName: l10n.appTitle,
                applicationVersion: ref.read(appVersionProvider).value,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// État des mises à jour ; une version plus récente s'ouvre d'un toucher sur sa page GitHub.
class _UpdateTile extends ConsumerWidget {
  const _UpdateTile({required this.onOpen});

  final Future<void> Function(Uri url) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final update = ref.watch(updateProvider);
    final release = update.release;
    final subtitle = switch (update.status) {
      UpdateStatus.unknown => l10n.updUnknown,
      UpdateStatus.checking => l10n.updChecking,
      UpdateStatus.upToDate => l10n.updUpToDate(update.installed ?? ''),
      UpdateStatus.available => l10n.updAvailable(release!.version),
      UpdateStatus.failed => l10n.updFailed,
    };
    return ListTile(
      leading: Icon(update.status == UpdateStatus.available ? Icons.new_releases_outlined : Icons.system_update_alt),
      title: Text(l10n.updTitle),
      subtitle: Semantics(liveRegion: true, child: Text(subtitle)),
      onTap: release == null ? null : () => onOpen(release.url),
      trailing: IconButton(
        tooltip: l10n.updCheckNow,
        onPressed: update.status == UpdateStatus.checking ? null : ref.read(updateProvider.notifier).check,
        icon: const Icon(Icons.refresh),
      ),
    );
  }
}

/// Titre d'une section, annoncé comme tel au lecteur d'écran.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Semantics(
        header: true,
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      ),
    );
  }
}

/// Un réglage à choisir dans une liste déroulante ; toute la ligne mesure au moins 56 dp.
class _DropdownTile<T> extends StatelessWidget {
  const _DropdownTile({required this.label, required this.value, required this.items, required this.onChanged});

  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: DropdownButtonFormField<T>(
        key: ValueKey(value),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
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
        leading: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        ),
        title: Text(label),
      ),
    );
  }
}


/// Adresse et jeton du service de compilation, avec un test de connexion.
class _CompileSettings extends ConsumerStatefulWidget {
  const _CompileSettings();

  @override
  ConsumerState<_CompileSettings> createState() => _CompileSettingsState();
}

class _CompileSettingsState extends ConsumerState<_CompileSettings> {
  late final TextEditingController _url;
  late final TextEditingController _token;
  bool _showToken = false;
  bool _testing = false;
  String? _result;
  bool _resultOk = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _url = TextEditingController(text: settings.compileServerUrl);
    _token = TextEditingController(text: settings.compileToken);
    // Les réglages se lisent de façon asynchrone : on remplit les champs une fois le fichier lu.
    ref.listenManual(settingsProvider.select((s) => s.loaded), (_, loaded) {
      if (!loaded) return;
      final current = ref.read(settingsProvider);
      if (_url.text.isEmpty) _url.text = current.compileServerUrl;
      if (_token.text.isEmpty) _token.text = current.compileToken;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    final l10n = context.l10n;
    setState(() {
      _testing = true;
      _result = null;
    });
    String message;
    var ok = false;
    try {
      final api = ref.read(compileApiProvider) ?? HttpCompileApi(baseUrl: _url.text, token: _token.text);
      final info = await api.health();
      await api.checkToken();
      message = l10n.settingsCompileTestOk(info.version);
      ok = true;
    } on CompileApiException catch (e) {
      message = compileApiErrorMessage(l10n, e);
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _result = message;
      _resultOk = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = ref.read(settingsProvider.notifier);
    final urlValid = _url.text.trim().isEmpty || isAcceptableServerUrl(_url.text);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.settingsCompileHint, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l10n.settingsCompileUrl,
              hintText: 'https://compile.example.com',
              errorText: urlValid ? null : l10n.settingsCompileUrlInvalid,
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) {
              setState(() => _result = null);
              controller.setCompileServerUrl(value);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: !_showToken,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l10n.settingsCompileToken,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _showToken ? l10n.settingsCompileTokenHide : l10n.settingsCompileTokenShow,
                onPressed: () => setState(() => _showToken = !_showToken),
                icon: Icon(_showToken ? Icons.visibility_off_outlined : Icons.visibility_outlined),
              ),
            ),
            onChanged: (value) {
              setState(() => _result = null);
              controller.setCompileToken(value);
            },
          ),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              onPressed: _testing || _url.text.trim().isEmpty || _token.text.isEmpty || !urlValid ? null : _test,
              icon: _testing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_tethering),
              label: Text(_testing ? l10n.settingsCompileTesting : l10n.settingsCompileTest),
            ),
          ),
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _result!,
                  style: TextStyle(color: _resultOk ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
