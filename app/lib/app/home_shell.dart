import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/editor/presentation/editor_page.dart';
import '../features/micropython/presentation/micropython_page.dart';
import '../features/serial_monitor/presentation/serial_monitor_page.dart';
import 'providers.dart';

/// Coque provisoire : un onglet par outil. Un seul outil doit tenir le port à la fois.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(homeTabProvider);
    // Clavier virtuel ouvert : la barre de navigation céderait sa place à la barre de symboles.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      body: IndexedStack(
        index: tab.index,
        children: const [SerialMonitorPage(), MicroPythonPage(), EditorPage()],
      ),
      bottomNavigationBar: keyboardOpen
          ? null
          : NavigationBar(
              selectedIndex: tab.index,
              onDestinationSelected: (i) => ref.read(homeTabProvider.notifier).show(HomeTab.values[i]),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.terminal), label: 'Moniteur série'),
                NavigationDestination(icon: Icon(Icons.memory), label: 'MicroPython'),
                NavigationDestination(icon: Icon(Icons.code), label: 'Éditeur'),
              ],
            ),
    );
  }
}
