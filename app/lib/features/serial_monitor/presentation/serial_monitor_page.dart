import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_hal/nomad_hal.dart' show TransportKind;

import '../../../l10n/error_messages.dart';
import '../../../l10n/l10n.dart';
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
    final transportKind = ref.watch(serialMonitorProvider.select((s) => s.transportKind));

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.monTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _StatusBadge(status: status, transportKind: transportKind),
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
  const _StatusBadge({required this.status, required this.transportKind});

  final ConnectionStatus status;
  final TransportKind? transportKind;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final (color, label) = switch (status) {
      ConnectionStatus.connected => (Colors.green, l10n.monStatusConnected),
      ConnectionStatus.connecting => (Colors.orange, l10n.monStatusConnecting),
      ConnectionStatus.disconnected => (scheme.outline, l10n.monStatusDisconnected),
    };
    return Tooltip(
      message: l10n.monTransportTooltip(transportKind == null ? '' : transportLabel(l10n, transportKind!)),
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
