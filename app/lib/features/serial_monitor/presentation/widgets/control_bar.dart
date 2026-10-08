import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/l10n.dart';
import '../../application/serial_monitor_controller.dart';

/// Lignes de contrôle, raccourcis REPL et options d'affichage.
class ControlBar extends ConsumerWidget {
  const ControlBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(serialMonitorProvider);
    final controller = ref.read(serialMonitorProvider.notifier);
    final connected = state.isConnected;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilterChip(
            label: const Text('DTR'),
            tooltip: l10n.monDtrTooltip,
            selected: state.dtr,
            onSelected: connected ? controller.setDtr : null,
          ),
          FilterChip(
            label: const Text('RTS'),
            tooltip: l10n.monRtsTooltip,
            selected: state.rts,
            onSelected: connected ? controller.setRts : null,
          ),
          ActionChip(
            avatar: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Reset'),
            tooltip: l10n.monResetTooltip,
            onPressed: connected ? controller.resetBoard : null,
          ),
          ActionChip(
            avatar: const Icon(Icons.memory, size: 18),
            label: Text(l10n.monBootloader),
            tooltip: l10n.monBootloaderTooltip,
            onPressed: connected ? controller.enterBootloader : null,
          ),
          ActionChip(
            label: const Text('Ctrl-C'),
            tooltip: l10n.monCtrlCTooltip,
            onPressed: connected ? () => controller.sendControl(0x03) : null,
          ),
          ActionChip(
            label: const Text('Ctrl-D'),
            tooltip: l10n.monCtrlDTooltip,
            onPressed: connected ? () => controller.sendControl(0x04) : null,
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: Text(l10n.monHex),
            tooltip: l10n.monHexTooltip,
            selected: state.hexView,
            onSelected: (_) => controller.toggleHexView(),
          ),
          FilterChip(
            label: Text(l10n.monTimestamp),
            selected: state.showTimestamps,
            onSelected: (_) => controller.toggleTimestamps(),
          ),
          ActionChip(
            avatar: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: Text(l10n.monClear),
            onPressed: controller.clearLog,
          ),
          Text(
            l10n.monByteCounters(_formatBytes(l10n, state.rxBytes), _formatBytes(l10n, state.txBytes)),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  static String _formatBytes(AppLocalizations l10n, int n) {
    if (n < 1024) return l10n.bytesB(n);
    if (n < 1024 * 1024) return l10n.bytesKb((n / 1024).toStringAsFixed(1));
    return l10n.bytesMb((n / (1024 * 1024)).toStringAsFixed(1));
  }
}
