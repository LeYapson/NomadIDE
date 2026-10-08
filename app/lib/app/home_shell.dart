import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/editor/application/editor_controller.dart';
import '../features/editor/presentation/editor_page.dart';
import '../features/micropython/presentation/micropython_page.dart';
import '../features/serial_monitor/presentation/serial_monitor_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../l10n/l10n.dart';
import 'providers.dart';

/// Coque provisoire : un onglet par outil. Un seul outil doit tenir le port à la fois.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
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
    // Clavier virtuel ouvert : la barre de navigation céderait sa place à la barre de symboles.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      body: IndexedStack(
        index: tab.index,
        children: const [SerialMonitorPage(), MicroPythonPage(), EditorPage(), SettingsPage()],
      ),
      bottomNavigationBar: keyboardOpen
          ? null
          : NavigationBar(
              selectedIndex: tab.index,
              onDestinationSelected: (i) => ref.read(homeTabProvider.notifier).show(HomeTab.values[i]),
              destinations: [
                NavigationDestination(icon: const Icon(Icons.terminal), label: context.l10n.navMonitor),
                NavigationDestination(icon: const Icon(Icons.memory), label: context.l10n.navMicroPython),
                NavigationDestination(icon: const Icon(Icons.code), label: context.l10n.navEditor),
                NavigationDestination(icon: const Icon(Icons.settings_outlined), label: context.l10n.navSettings),
              ],
            ),
    );
  }
}
