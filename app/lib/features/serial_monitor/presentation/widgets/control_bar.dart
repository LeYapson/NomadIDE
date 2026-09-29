import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/serial_monitor_controller.dart';

/// Lignes de contrôle, raccourcis REPL et options d'affichage.
class ControlBar extends ConsumerWidget {
  const ControlBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            tooltip: 'Data Terminal Ready',
            selected: state.dtr,
            onSelected: connected ? controller.setDtr : null,
          ),
          FilterChip(
            label: const Text('RTS'),
            tooltip: 'Request To Send',
            selected: state.rts,
            onSelected: connected ? controller.setRts : null,
          ),
          ActionChip(
            avatar: const Icon(Icons.restart_alt, size: 18),
            label: const Text('Reset'),
            tooltip: 'Reset matériel via RTS (cartes ESP32/ESP8266 à circuit auto-reset)',
            onPressed: connected ? controller.resetBoard : null,
          ),
          ActionChip(
            avatar: const Icon(Icons.memory, size: 18),
            label: const Text('Bootloader'),
            tooltip: "Séquence esptool : redémarre l'ESP32 en mode téléchargement",
            onPressed: connected ? controller.enterBootloader : null,
          ),
          ActionChip(
            label: const Text('Ctrl-C'),
            tooltip: 'Interrompre le programme (MicroPython)',
            onPressed: connected ? () => controller.sendControl(0x03) : null,
          ),
          ActionChip(
            label: const Text('Ctrl-D'),
            tooltip: 'Soft reboot (MicroPython)',
            onPressed: connected ? () => controller.sendControl(0x04) : null,
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('HEX'),
            tooltip: 'Afficher les octets en hexadécimal',
            selected: state.hexView,
            onSelected: (_) => controller.toggleHexView(),
          ),
          FilterChip(
            label: const Text('Horodatage'),
            selected: state.showTimestamps,
            onSelected: (_) => controller.toggleTimestamps(),
          ),
          ActionChip(
            avatar: const Icon(Icons.delete_sweep_outlined, size: 18),
            label: const Text('Effacer'),
            onPressed: controller.clearLog,
          ),
          Text(
            'RX ${_formatBytes(state.rxBytes)} · TX ${_formatBytes(state.txBytes)}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }

  static String _formatBytes(int n) {
    if (n < 1024) return '$n o';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} Ko';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }
}
