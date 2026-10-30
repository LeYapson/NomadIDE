import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_protocols/nomad_protocols.dart';

import '../../../app/theme.dart';
import '../../../l10n/l10n.dart';
import '../../../ui/ui.dart';
import '../application/flash_controller.dart';
import '../data/firmware_catalog.dart';
import 'esp_flash_view.dart';
import 'firmware_card.dart';

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

/// Flashage d'un fichier `.uf2` sur une carte RP2040 / RP2350 (Pico, Badger 2040…), en trois étapes :
/// fichier, carte, écriture. Une étape terminée se replie sur son résumé.
class Uf2FlashView extends ConsumerWidget {
  const Uf2FlashView({super.key});

  static const _steps = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(flashProvider);
    final controller = ref.read(flashProvider.notifier);
    final supported = ref.watch(uf2SupportedProvider);

    final file = state.file;
    final fileInfo = file == null
        ? null
        : l10n.flashFileInfo(
            file.family == Uf2Family.unknown ? l10n.flashFamilyUnknown : file.family.label,
            flashSizeLabel(l10n, file.payloadSize),
            file.blockCount,
          );
    final boardFound = state.drive != null || state.bootselUsb;
    final boardLine = state.drive != null
        ? l10n.flashDriveFound(state.drive!.path, state.drive!.boardId)
        : state.bootselUsb
            ? l10n.flashBootselUsbFound
            : state.selectedDevice?.displayName;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!supported) ...[
            StatusBanner(message: l10n.flashUnsupported, kind: StatusKind.info),
            const SizedBox(height: 12),
          ],
          StepCard(
            number: 1,
            total: _steps,
            title: l10n.flashStepFile,
            done: file != null,
            summary: file == null
                ? null
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(state.fileName ?? '', style: Theme.of(context).textTheme.titleSmall),
                      Text(fileInfo!, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
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
              if (file == null)
                Text(state.fileName ?? l10n.flashNoFile)
              else ...[
                Text(state.fileName ?? '', style: Theme.of(context).textTheme.titleSmall),
                Text(fileInfo!),
              ],
              if (supported)
                FirmwareCard(
                  boards: const [
                    FirmwareBoard.badger2040,
                    FirmwareBoard.badger2040w,
                    FirmwareBoard.pico,
                    FirmwareBoard.picoW,
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
            done: boardLine != null,
            summary: boardLine == null ? null : Text(boardLine),
            children: [
              if (boardFound)
                Row(
                  children: [
                    Icon(Icons.check_circle, color: context.nomadColors.success, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(boardLine!)),
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
                    onPressed: supported && state.canFlash ? controller.flash : null,
                    icon: Icons.bolt,
                    label: l10n.flashRun,
                  ),
                ],
              ),
              if (file == null && !state.working) ...[
                const SizedBox(height: 8),
                Text(l10n.flashRunBlocked, style: Theme.of(context).textTheme.bodySmall),
              ],
              if (state.working) ...[
                const SizedBox(height: 12),
                ProgressStatus(
                  label: _phaseLabel(l10n, state),
                  spokenLabel: _phaseLabel(l10n, state, coarse: true),
                  value: _hasProgress(state.phase) ? _fraction(state) : null,
                ),
              ],
              if (state.message != null) ...[
                const SizedBox(height: 12),
                StatusBanner(message: state.message!, kind: state.succeeded ? StatusKind.success : StatusKind.error),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static double? _fraction(FlashState s) => s.total <= 0 ? null : (s.done / s.total).clamp(0.0, 1.0);

  /// Phases dont l'avancement est connu (les autres affichent une barre indéterminée).
  static bool _hasProgress(FlashPhase phase) =>
      phase == FlashPhase.erasing || phase == FlashPhase.copying || phase == FlashPhase.verifying;

  /// Pourcentage affiché, ou arrondi au palier annoncé au lecteur d'écran ([coarse]).
  static int _percent(FlashState s, bool coarse) =>
      coarse ? announcedPercent(_fraction(s)) : ((_fraction(s) ?? 0) * 100).round();

  static String _phaseLabel(AppLocalizations l10n, FlashState s, {bool coarse = false}) => switch (s.phase) {
        FlashPhase.touching => l10n.flashPhaseTouching,
        FlashPhase.waitingDrive => l10n.flashPhaseWaiting,
        FlashPhase.permission => l10n.flashPhasePermission,
        FlashPhase.erasing => l10n.flashPhaseErasing(_percent(s, coarse)),
        FlashPhase.verifying => l10n.flashPhaseVerifying(_percent(s, coarse)),
        FlashPhase.copying => l10n.flashPhaseCopying(_percent(s, coarse)),
        FlashPhase.rebooting => l10n.flashPhaseRebooting,
        _ => '',
      };
}
