import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_protocols/nomad_protocols.dart';

import '../../../l10n/l10n.dart';
import '../application/flash_controller.dart';
import 'esp_flash_view.dart';
import 'flash_widgets.dart';

enum _FlashTarget { rp2, esp }

/// Onglet « Flasher » : un fichier `.uf2` pour les RP2040 / RP2350, un `.bin` pour les ESP.
class FlashPage extends StatefulWidget {
  const FlashPage({super.key});

  @override
  State<FlashPage> createState() => _FlashPageState();
}

class _FlashPageState extends State<FlashPage> {
  _FlashTarget _target = _FlashTarget.rp2;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.flashTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<_FlashTarget>(
              segments: [
                ButtonSegment(value: _FlashTarget.rp2, label: Text(l10n.flashTargetRp2)),
                ButtonSegment(value: _FlashTarget.esp, label: Text(l10n.flashTargetEsp)),
              ],
              showSelectedIcon: false,
              selected: {_target},
              onSelectionChanged: (s) => setState(() => _target = s.first),
            ),
          ),
          Expanded(child: _target == _FlashTarget.rp2 ? const Uf2FlashView() : const EspFlashView()),
        ],
      ),
    );
  }
}

/// Flashage d'un fichier `.uf2` sur une carte RP2040 / RP2350 (Pico, Badger 2040…).
class Uf2FlashView extends ConsumerWidget {
  const Uf2FlashView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(flashProvider);
    final controller = ref.read(flashProvider.notifier);
    final supported = ref.watch(uf2SupportedProvider);
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!supported)
              Card(
                color: scheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
                      const SizedBox(width: 12),
                      Expanded(child: Text(l10n.flashUnsupported, style: TextStyle(color: scheme.onSecondaryContainer))),
                    ],
                  ),
                ),
              ),
            FlashStep(
              title: l10n.flashStepFile,
              children: [
                Wrap(
                  children: [
                    OutlinedButton.icon(
                      onPressed: state.working ? null : controller.pickFile,
                      icon: const Icon(Icons.folder_open),
                      label: Text(l10n.flashPickFile),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (state.file == null)
                  Text(state.fileName ?? l10n.flashNoFile)
                else ...[
                  Text(state.fileName ?? '', style: Theme.of(context).textTheme.titleSmall),
                  Text(l10n.flashFileInfo(
                    state.file!.family == Uf2Family.unknown ? l10n.flashFamilyUnknown : state.file!.family.label,
                    flashSizeLabel(l10n, state.file!.payloadSize),
                    state.file!.blockCount,
                  )),
                ],
              ],
            ),
            FlashStep(
              title: l10n.flashStepBoard,
              children: [
                if (state.drive != null)
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: scheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(l10n.flashDriveFound(state.drive!.path, state.drive!.boardId))),
                    ],
                  )
                else ...[
                  if (state.devices.isNotEmpty)
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
                  Text(l10n.flashDriveNone),
                ],
                const SizedBox(height: 4),
                Text(l10n.flashBoardHint, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            FlashStep(
              title: l10n.flashStepRun,
              children: [
                Wrap(
                  children: [
                    FilledButton.icon(
                      onPressed: supported && state.canFlash ? controller.flash : null,
                      icon: const Icon(Icons.bolt),
                      label: Text(l10n.flashRun),
                    ),
                  ],
                ),
                if (state.working) ...[
                  const SizedBox(height: 12),
                  Text(_phaseLabel(l10n, state)),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: state.phase == FlashPhase.copying ? _fraction(state) : null),
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

  static double? _fraction(FlashState s) => s.total <= 0 ? null : (s.done / s.total).clamp(0.0, 1.0);

  static String _phaseLabel(AppLocalizations l10n, FlashState s) => switch (s.phase) {
        FlashPhase.touching => l10n.flashPhaseTouching,
        FlashPhase.waitingDrive => l10n.flashPhaseWaiting,
        FlashPhase.copying => l10n.flashPhaseCopying(((_fraction(s) ?? 0) * 100).round()),
        FlashPhase.rebooting => l10n.flashPhaseRebooting,
        _ => '',
      };
}
