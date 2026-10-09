import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_hal/nomad_hal.dart';

import '../../../l10n/l10n.dart';
import '../application/esp_flash_controller.dart';
import '../application/flash_controller.dart' show flashSizeLabel;
import 'flash_widgets.dart';

/// Flashage d'un fichier `.bin` sur un ESP32 / ESP8266, par le bootloader de la ROM.
class EspFlashView extends ConsumerStatefulWidget {
  const EspFlashView({super.key});

  @override
  ConsumerState<EspFlashView> createState() => _EspFlashViewState();
}

class _EspFlashViewState extends ConsumerState<EspFlashView> {
  late final TextEditingController _offset = TextEditingController(text: ref.read(espFlashProvider).offsetText);

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(espFlashProvider);
    final controller = ref.read(espFlashProvider.notifier);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FlashStep(
            title: l10n.flashStepFile,
            children: [
              Wrap(
                children: [
                  OutlinedButton.icon(
                    onPressed: state.working ? null : controller.pickFile,
                    icon: const Icon(Icons.folder_open),
                    label: Text(l10n.espPickFile),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (state.bytes == null)
                Text(l10n.flashNoFile)
              else ...[
                Text(state.fileName ?? '', style: Theme.of(context).textTheme.titleSmall),
                Text(l10n.espFileInfo(flashSizeLabel(l10n, state.bytes!.length))),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _offset,
                enabled: !state.working,
                onChanged: controller.setOffset,
                decoration: InputDecoration(
                  labelText: l10n.espOffsetLabel,
                  helperText: l10n.espOffsetHelper,
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          FlashStep(
            title: l10n.flashStepBoard,
            children: [
              if (state.devices.isEmpty)
                Text(l10n.espNoBoard)
              else
                DropdownButtonFormField<SerialDeviceInfo>(
                  key: ValueKey(state.selectedDevice),
                  initialValue: state.selectedDevice,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.monBoardLabel, border: const OutlineInputBorder()),
                  items: [
                    for (final d in state.devices)
                      DropdownMenuItem(value: d, child: Text('${d.displayName} · ${d.details}', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: state.working ? null : controller.selectDevice,
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: ValueKey(state.baudRate),
                initialValue: state.baudRate,
                decoration: InputDecoration(labelText: l10n.espBaudLabel, border: const OutlineInputBorder()),
                items: [for (final b in espWriteBauds) DropdownMenuItem(value: b, child: Text('$b'))],
                onChanged: state.working ? null : (b) => controller.setBaudRate(b ?? state.baudRate),
              ),
              const SizedBox(height: 8),
              Text(l10n.espBoardHint, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          FlashStep(
            title: l10n.flashStepRun,
            children: [
              Wrap(
                children: [
                  FilledButton.icon(
                    onPressed: state.canFlash ? controller.flash : null,
                    icon: const Icon(Icons.bolt),
                    label: Text(l10n.flashRun),
                  ),
                ],
              ),
              if (state.working) ...[
                const SizedBox(height: 12),
                Text(_phaseLabel(l10n, state)),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: state.phase == EspFlashPhase.writing ? _fraction(state) : null),
              ],
              if (state.message != null) ...[
                const SizedBox(height: 12),
                FlashBanner(message: state.message!, success: state.succeeded),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static double? _fraction(EspFlashState s) => s.total <= 0 ? null : (s.done / s.total).clamp(0.0, 1.0);

  static String _phaseLabel(AppLocalizations l10n, EspFlashState s) => switch (s.phase) {
        EspFlashPhase.connecting => l10n.espPhaseConnecting,
        EspFlashPhase.writing => l10n.espPhaseWriting(((_fraction(s) ?? 0) * 100).round()),
        EspFlashPhase.verifying => l10n.espPhaseVerifying,
        EspFlashPhase.restarting => l10n.espPhaseRestarting,
        _ => '',
      };
}
