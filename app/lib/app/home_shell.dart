import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/editor/application/editor_controller.dart';
import '../features/editor/presentation/editor_page.dart';
import '../features/flash/presentation/flash_page.dart';
import '../features/micropython/presentation/micropython_page.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/serial_monitor/presentation/serial_monitor_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../l10n/l10n.dart';
import 'providers.dart';
import 'settings.dart';

/// Coque provisoire : un onglet par outil. Un seul outil doit tenir le port à la fois.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late final AppLifecycleListener _lifecycle;
  bool _onboardingShown = false;

  /// Premier lancement : le tutoriel s'ouvre une fois les réglages lus (jamais avant, pour ne pas
  /// l'afficher une fraction de seconde à quelqu'un qui l'a déjà suivi).
  void _maybeShowOnboarding(AppSettings settings) {
    if (debugSkipOnboarding || _onboardingShown || !settings.loaded || settings.onboardingDone) return;
    _onboardingShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showOnboarding(context);
    });
  }

  @override
  void initState() {
    super.initState();
    // Réglages peut-être déjà lus avant la construction de la coque.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeShowOnboarding(ref.read(settingsProvider));
    });
    // Android peut tuer l'application une fois en arrière-plan : on écrit les
    // brouillons avant, sans attendre le délai habituel.
    _lifecycle = AppLifecycleListener(
      onInactive: _flushDrafts,
      onHide: _flushDrafts,
      onPause: _flushDrafts,
      onDetach: _flushDrafts,
    );
  }

  void _flushDrafts() => ref.read(editorProvider.notifier).flushDrafts();

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(homeTabProvider);
    ref.listen(settingsProvider, (_, next) => _maybeShowOnboarding(next));
    // Clavier virtuel ouvert : la barre de navigation céderait sa place à la barre de symboles.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    // Chaque destination mesure largeur / 5 : sur téléphone (~72 dp), « MicroPython » passe sur deux lignes
    // et décale toute la barre. Le nom court suffit là ; le nom complet reste dans l'info-bulle.
    final narrow = MediaQuery.sizeOf(context).width < 480;

    return Scaffold(
      body: IndexedStack(
        index: tab.index,
        children: const [SerialMonitorPage(), MicroPythonPage(), EditorPage(), FlashPage(), SettingsPage()],
      ),
      bottomNavigationBar: keyboardOpen
          ? null
          : NavigationBar(
              selectedIndex: tab.index,
              onDestinationSelected: (i) => ref.read(homeTabProvider.notifier).show(HomeTab.values[i]),
              destinations: [
                NavigationDestination(icon: const Icon(Icons.terminal), label: context.l10n.navMonitor),
                NavigationDestination(
                  icon: const Icon(Icons.memory),
                  label: narrow ? context.l10n.navMicroPythonShort : context.l10n.navMicroPython,
                  tooltip: context.l10n.navMicroPython,
                ),
                NavigationDestination(icon: const Icon(Icons.code), label: context.l10n.navEditor),
                NavigationDestination(icon: const Icon(Icons.bolt), label: context.l10n.navFlash),
                NavigationDestination(icon: const Icon(Icons.settings_outlined), label: context.l10n.navSettings),
              ],
            ),
    );
  }
}
