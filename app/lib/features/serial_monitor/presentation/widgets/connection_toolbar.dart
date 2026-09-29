import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_hal/nomad_hal.dart';

import '../../application/serial_monitor_controller.dart';
import '../../application/serial_monitor_state.dart';

/// Choix de la carte, du débit, et bouton de connexion.
/// Un `Wrap` place les contrôles sur plusieurs lignes sur téléphone.
class ConnectionToolbar extends ConsumerWidget {
  const ConnectionToolbar({super.key});

  static const _fieldDecoration = InputDecoration(
    border: OutlineInputBorder(),
    isDense: true,
    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(serialMonitorProvider);
    final controller = ref.read(serialMonitorProvider.notifier);
    final idle = state.status == ConnectionStatus.disconnected;
    final deviceFieldWidth = (MediaQuery.sizeOf(context).width - 32).clamp(200.0, 380.0).toDouble();

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: deviceFieldWidth,
            child: InputDecorator(
              decoration: _fieldDecoration.copyWith(labelText: 'Carte'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<SerialDeviceInfo>(
                  isDense: true,
                  isExpanded: true,
                  // DropdownButton exige que la valeur figure dans la liste.
                  value: state.devices.contains(state.selectedDevice) ? state.selectedDevice : null,
                  hint: Text(state.devices.isEmpty ? 'Aucune carte détectée' : 'Choisir une carte'),
                  items: [
                    for (final device in state.devices)
                      DropdownMenuItem(value: device, child: _DeviceLabel(device: device)),
                  ],
                  onChanged: idle
                      ? (device) {
                          if (device != null) controller.selectDevice(device);
                        }
                      : null,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Actualiser la liste',
            onPressed: idle ? controller.refreshDevices : null,
            icon: const Icon(Icons.refresh),
          ),
          SizedBox(
            width: 150,
            child: InputDecorator(
              decoration: _fieldDecoration.copyWith(labelText: 'Débit (bauds)'),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isDense: true,
                  isExpanded: true,
                  value: state.config.baudRate,
                  items: [
                    for (final baud in SerialConfig.standardBaudRates)
                      DropdownMenuItem(value: baud, child: Text('$baud')),
                  ],
                  onChanged: state.status == ConnectionStatus.connecting
                      ? null
                      : (baud) {
                          if (baud != null) controller.setBaudRate(baud);
                        },
                ),
              ),
            ),
          ),
          switch (state.status) {
            ConnectionStatus.disconnected => FilledButton.icon(
                onPressed: state.selectedDevice == null ? null : controller.connect,
                icon: const Icon(Icons.usb),
                label: const Text('Connecter'),
              ),
            ConnectionStatus.connecting => FilledButton.icon(
                onPressed: null,
                icon: const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                label: const Text('Connexion…'),
              ),
            ConnectionStatus.connected => FilledButton.tonalIcon(
                onPressed: controller.disconnect,
                icon: const Icon(Icons.usb_off),
                label: const Text('Déconnecter'),
              ),
          },
        ],
      ),
    );
  }
}

class _DeviceLabel extends StatelessWidget {
  const _DeviceLabel({required this.device});

  final SerialDeviceInfo device;

  @override
  Widget build(BuildContext context) {
    final details = device.details;
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: device.displayName),
        if (details.isNotEmpty)
          TextSpan(
            text: '   $details',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
