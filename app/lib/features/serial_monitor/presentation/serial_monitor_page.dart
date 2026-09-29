import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/serial_monitor_controller.dart';
import '../application/serial_monitor_state.dart';
import 'widgets/connection_toolbar.dart';
import 'widgets/control_bar.dart';
import 'widgets/serial_input_bar.dart';
import 'widgets/serial_log_view.dart';

class SerialMonitorPage extends ConsumerWidget {
  const SerialMonitorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Chaque nouvelle erreur (permission refusée, port occupé, débranchement…) → SnackBar.
    ref.listen<String?>(serialMonitorProvider.select((s) => s.errorMessage), (previous, next) {
      if (next != null && next != previous) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next)));
      }
    });
    final status = ref.watch(serialMonitorProvider.select((s) => s.status));
    final transportName = ref.watch(serialMonitorProvider.select((s) => s.transportName));

    return Scaffold(
      appBar: AppBar(
        title: const Text('NomadMCU · Moniteur série'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _StatusBadge(status: status, transportName: transportName),
          ),
        ],
      ),
      body: const SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConnectionToolbar(),
            ControlBar(),
            Divider(height: 1),
            Expanded(child: SerialLogView()),
            Divider(height: 1),
            SerialInputBar(),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.transportName});

  final ConnectionStatus status;
  final String transportName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, label) = switch (status) {
      ConnectionStatus.connected => (Colors.green, 'Connecté'),
      ConnectionStatus.connecting => (Colors.orange, 'Connexion…'),
      ConnectionStatus.disconnected => (scheme.outline, 'Déconnecté'),
    };
    return Tooltip(
      message: 'Transport : $transportName',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}
