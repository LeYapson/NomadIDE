import 'package:flutter/material.dart';

import '../features/micropython/presentation/micropython_page.dart';
import '../features/serial_monitor/presentation/serial_monitor_page.dart';

/// Coque provisoire : un onglet par outil. Un seul outil doit tenir le port à la fois.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: const [SerialMonitorPage(), MicroPythonPage()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.terminal), label: 'Moniteur série'),
          NavigationDestination(icon: Icon(Icons.memory), label: 'MicroPython'),
        ],
      ),
    );
  }
}
