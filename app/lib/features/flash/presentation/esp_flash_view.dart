import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_hal/nomad_hal.dart';

import '../../../l10n/l10n.dart';
import '../../../ui/ui.dart';
import '../application/esp_flash_controller.dart';
import '../application/flash_controller.dart' show flashSizeLabel;
import '../data/firmware_catalog.dart';
import 'firmware_card.dart';

/// Flashage d'un fichier `.bin` sur un ESP32 / ESP8266, par le bootloader de la ROM, en trois étapes :
/// fichier, carte, écriture. L'adresse et la vitesse d'écriture sont dans les options avancées : l'adresse
/// est déduite de l'en-tête du fichier, il n'y a normalement rien à y toucher.
class EspFlashView extends ConsumerStatefulWidget {
  const EspFlashView({super.key});

  @override
  ConsumerState<EspFlashView> createState() => _EspFlashViewState();
}

class _EspFlashViewState extends ConsumerState<EspFlashView> {
  static const _steps = 3;

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

    // L'adresse peut être choisie par le contrôleur (d'après l'en-tête du fichier) : le champ la suit.
    ref.listen(espFlashProvider.select((s) => s.offsetText), (_, text) {
      if (_offset.text != text) _offset.text = text;
    });

    final bytes = state.bytes;
    final device = state.selectedDevice;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StepCard(
            number: 1,
            total: _steps,
            title: l10n.flashStepFile,
            done: bytes != null,
            summary: bytes == null
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(state.fileName ?? '', style: Theme.of(context).textTheme.titleSmall),
                      Text(l10n.espFileInfo(flashSizeLabel(l10n, bytes.length)), style: Theme.of(context).textTheme.bodySmall),
                      if (state.offsetNote != null) Text(state.offsetNote!, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
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
              if (bytes == null)
                Text(l10n.flashNoFile)
              else ...[
                Text(state.fileName ?? '', style: Theme.of(context).textTheme.titleSmall),
                Text(l10n.espFileInfo(flashSizeLabel(l10n, bytes.length))),
                if (state.offsetNote != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.auto_fix_high, size: 18, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text(state.offsetNote!, style: Theme.of(context).textTheme.bodySmall)),
                      ],
                    ),
                  ),
              ],
              FirmwareCard(
                boards: const [
                  FirmwareBoard.esp32,
                  FirmwareBoard.esp32s3,
                  FirmwareBoard.esp32c3,
                  FirmwareBoard.esp32s2,
                  FirmwareBoard.esp32c6,
                ],
                onFile: controller.useFile,
                enabled: !state.working,
                initiallyExpanded: false,
              ),
            ],
          ),
          StepCard(
            number: 2,
            total: _steps,
            title: l10n.flashStepBoard,
            done: device != null,
            summary: device == null ? null : Text('${device.displayName} · ${device.details}'),
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
              const SizedBox(height: 8),
              Text(l10n.espBoardHint, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          StepCard(
            number: 3,
            total: _steps,
            title: l10n.flashStepRun,
            done: state.succeeded,
            collapsible: false,
            children: [
              Wrap(
                children: [
                  HardwareButton(
                    onPressed: state.canFlash ? controller.flash : null,
                    icon: Icons.bolt,
                    label: l10n.flashRun,
                  ),
                ],
              ),
              if (bytes == null && !state.working) ...[
                const SizedBox(height: 8),
                Text(l10n.flashRunBlocked, style: Theme.of(context).textTheme.bodySmall),
              ],
              if (state.working) ...[
                const SizedBox(height: 12),
                ProgressStatus(
                  label: _phaseLabel(l10n, state),
                  value: state.phase == EspFlashPhase.writing ? _fraction(state) : null,
                ),
              ],
              if (state.message != null) ...[
                const SizedBox(height: 12),
                StatusBanner(message: state.message!, kind: state.succeeded ? StatusKind.success : StatusKind.error),
              ],
              Disclosure(
                title: l10n.advancedTitle,
                summary: l10n.espAdvancedSummary(state.offsetText, state.baudRate),
                children: [
                  const SizedBox(height: 4),
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
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    key: ValueKey(state.baudRate),
                    initialValue: state.baudRate,
                    decoration: InputDecoration(labelText: l10n.espBaudLabel, border: const OutlineInputBorder()),
                    items: [for (final b in espWriteBauds) DropdownMenuItem(value: b, child: Text('$b'))],
                    onChanged: state.working ? null : (b) => controller.setBaudRate(b ?? state.baudRate),
                  ),
                ],
              ),
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
