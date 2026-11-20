import 'package:flutter/material.dart';
import 'package:nomad_hal/nomad_hal.dart';

import '../../l10n/l10n.dart';

/// Liste déroulante des cartes détectées (« Carte »), identique dans le Moniteur et dans MicroPython.
/// Largeur : celle de l'écran moins les marges, entre 200 et 380 dp. [enabled] faux : liste figée (carte connectée).
class BoardDropdown extends StatelessWidget {
  const BoardDropdown({super.key, required this.devices, required this.selected, required this.enabled, required this.onSelected});

  final List<SerialDeviceInfo> devices;
  final SerialDeviceInfo? selected;
  final bool enabled;
  final ValueChanged<SerialDeviceInfo> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final width = (MediaQuery.sizeOf(context).width - 32).clamp(200.0, 380.0).toDouble();
    return SizedBox(
      width: width,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.monBoardLabel,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<SerialDeviceInfo>(
            isExpanded: true,
            // DropdownButton exige que la valeur figure dans la liste.
            value: devices.contains(selected) ? selected : null,
            hint: Text(devices.isEmpty ? l10n.monNoBoardDetected : l10n.monChooseBoard),
            items: [
              for (final device in devices) DropdownMenuItem(value: device, child: _DeviceLabel(device: device)),
            ],
            onChanged: enabled
                ? (device) {
                    if (device != null) onSelected(device);
                  }
                : null,
          ),
        ),
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
        if (details.isNotEmpty) TextSpan(text: '   $details', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
