import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_hal/nomad_hal.dart' show TransportKind;

import '../../../app/theme.dart';
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
      body: SafeArea(
        // Les contrôles du haut sont limités à la moitié de la hauteur et défilent au-delà : avec un texte
        // agrandi, ils ne doivent ni déborder ni chasser le journal.
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.5),
                child: const SingleChildScrollView(
                  child: Column(children: [ConnectionToolbar(), ControlBar()]),
                ),
              ),
              const Divider(height: 1),
              const Expanded(child: SerialLogView()),
              const Divider(height: 1),
              const SerialInputBar(),
            ],
          ),
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
      ConnectionStatus.connected => (context.nomadColors.success, l10n.monStatusConnected),
      ConnectionStatus.connecting => (context.nomadColors.hardware, l10n.monStatusConnecting),
      ConnectionStatus.disconnected => (scheme.outline, l10n.monStatusDisconnected),
    };
    final transport = l10n.monTransportTooltip(transportKind == null ? '' : transportLabel(l10n, transportKind!));
    return Semantics(
      liveRegion: true,
      container: true,
      label: label,
      hint: transport,
      excludeSemantics: true,
      child: Tooltip(
        message: transport,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 10, color: color),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      ),
    );
  }
}
