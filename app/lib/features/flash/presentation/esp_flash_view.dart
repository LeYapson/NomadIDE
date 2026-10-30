import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_hal/nomad_hal.dart';

import '../../../l10n/l10n.dart';
import '../../../ui/ui.dart';
import '../application/esp_flash_controller.dart';
import '../application/flash_controller.dart' show flashSizeLabel;
import '../data/firmware_catalog.dart';
import 'firmware_card.dart';

/// Flashage d'un ou plusieurs fichiers `.bin` sur un ESP32 / ESP8266, par le bootloader de la ROM, en
/// trois étapes : fichier(s), carte, écriture.
///
/// Un seul fichier (cas courant, firmware MicroPython) : son adresse est déduite de l'en-tête et rangée
/// dans les options avancées. Plusieurs fichiers (projet Arduino ou ESP-IDF : bootloader, table de
/// partitions, application) : chacun montre son adresse, modifiable, et ils sont écrits en une passe.
class EspFlashView extends ConsumerStatefulWidget {
  const EspFlashView({super.key});

  @override
  ConsumerState<EspFlashView> createState() => _EspFlashViewState();
}

class _EspFlashViewState extends ConsumerState<EspFlashView> {
  static const _steps = 3;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(espFlashProvider);
    final controller = ref.read(espFlashProvider.notifier);
    final textTheme = Theme.of(context).textTheme;

    final parts = state.parts;
    final device = state.selectedDevice;
    final idle = !state.working;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StepCard(
            number: 1,
            total: _steps,
            title: l10n.flashStepFile,
            done: parts.isNotEmpty,
            summary: parts.isEmpty ? null : _FilesSummary(state: state),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: idle ? controller.pickFile : null,
                    icon: const Icon(Icons.folder_open),
                    label: Text(l10n.espPickFile),
                  ),
                  if (parts.isNotEmpty)
                    Tooltip(
                      message: l10n.espMultiHint,
                      child: OutlinedButton.icon(
                        onPressed: idle ? controller.addFile : null,
                        icon: const Icon(Icons.add),
                        label: Text(l10n.espAddFile),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (parts.isEmpty)
                Text(l10n.flashNoFile)
              else if (!state.multiple) ...[
                Text(parts.first.name, style: textTheme.titleSmall),
                Text(l10n.espFileInfo(flashSizeLabel(l10n, parts.first.bytes.length))),
                if (parts.first.note != null) _Note(text: parts.first.note!),
              ] else ...[
                Text(l10n.espMultiHint, style: textTheme.bodySmall),
                for (var i = 0; i < parts.length; i++)
                  _PartRow(
                    key: ValueKey('${parts[i].name}#$i'),
                    part: parts[i],
                    enabled: idle,
                    onOffset: (text) => controller.setOffset(text, index: i),
                    onRemove: () => controller.removePart(i),
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
                enabled: idle,
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
                  onChanged: idle ? controller.selectDevice : null,
                ),
              const SizedBox(height: 8),
              Text(l10n.espBoardHint, style: textTheme.bodySmall),
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
              if (parts.isEmpty && idle) ...[
                const SizedBox(height: 8),
                Text(l10n.flashRunBlocked, style: textTheme.bodySmall),
              ],
              if (state.working) ...[
                const SizedBox(height: 12),
                ProgressStatus(
                  label: _phaseLabel(l10n, state),
                  spokenLabel: _phaseLabel(l10n, state, coarse: true),
                  value: state.phase == EspFlashPhase.writing ? _fraction(state) : null,
                ),
              ],
              if (state.message != null) ...[
                const SizedBox(height: 12),
                StatusBanner(message: state.message!, kind: state.succeeded ? StatusKind.success : StatusKind.error),
              ],
              Disclosure(
                title: l10n.advancedTitle,
                summary: state.multiple
                    ? l10n.espBaudSummary(state.baudRate)
                    : l10n.espAdvancedSummary(state.offsetText, state.baudRate),
                children: [
                  const SizedBox(height: 4),
                  // Avec plusieurs fichiers, chaque adresse est affichée à côté de son fichier (étape 1).
                  if (!state.multiple) ...[
                    _OffsetField(
                      value: state.offsetText,
                      enabled: idle,
                      label: l10n.espOffsetLabel,
                      helper: l10n.espOffsetHelper,
                      onChanged: controller.setOffset,
                    ),
                    const SizedBox(height: 12),
                  ],
                  DropdownButtonFormField<int>(
                    key: ValueKey(state.baudRate),
                    initialValue: state.baudRate,
                    decoration: InputDecoration(labelText: l10n.espBaudLabel, border: const OutlineInputBorder()),
                    items: [for (final b in espWriteBauds) DropdownMenuItem(value: b, child: Text('$b'))],
                    onChanged: idle ? (b) => controller.setBaudRate(b ?? state.baudRate) : null,
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

  /// Pourcentage affiché, ou arrondi au palier annoncé au lecteur d'écran ([coarse]).
  static int _percent(EspFlashState s, bool coarse) =>
      coarse ? announcedPercent(_fraction(s)) : ((_fraction(s) ?? 0) * 100).round();

  static String _phaseLabel(AppLocalizations l10n, EspFlashState s, {bool coarse = false}) => switch (s.phase) {
        EspFlashPhase.connecting => l10n.espPhaseConnecting,
        EspFlashPhase.writing => s.multiple
            ? l10n.espPhaseWritingPart(s.parts[s.currentPart].name, s.currentPart + 1, s.parts.length, _percent(s, coarse))
            : l10n.espPhaseWriting(_percent(s, coarse)),
        EspFlashPhase.verifying => l10n.espPhaseVerifying,
        EspFlashPhase.restarting => l10n.espPhaseRestarting,
        _ => '',
      };
}

/// Résumé de l'étape 1 repliée : le fichier et son adresse, ou la liste des fichiers.
class _FilesSummary extends StatelessWidget {
  const _FilesSummary({required this.state});

  final EspFlashState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    final first = state.parts.first;
    if (!state.multiple) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(first.name, style: textTheme.titleSmall),
          Text(l10n.espFileInfo(flashSizeLabel(l10n, first.bytes.length)), style: textTheme.bodySmall),
          if (first.note != null) Text(first.note!, style: textTheme.bodySmall),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.espPartsSummary(state.parts.length, flashSizeLabel(l10n, state.totalBytes)), style: textTheme.titleSmall),
        for (final p in state.parts) Text('${p.offsetText} · ${p.name}', style: textTheme.bodySmall),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_fix_high, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}

/// Un fichier d'un flash en plusieurs parties : nom, taille, ce que l'app en a compris, adresse.
class _PartRow extends StatelessWidget {
  const _PartRow({super.key, required this.part, required this.enabled, required this.onOffset, required this.onRemove});

  final EspFilePart part;
  final bool enabled;
  final ValueChanged<String> onOffset;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
      decoration: BoxDecoration(border: Border.all(color: scheme.outlineVariant), borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${part.name} · ${flashSizeLabel(l10n, part.bytes.length)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: l10n.espRemoveFile(part.name),
                onPressed: enabled ? onRemove : null,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (part.note != null)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 8),
              child: Text(part.note!, style: Theme.of(context).textTheme.bodySmall),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _OffsetField(
              value: part.offsetText,
              enabled: enabled,
              label: l10n.espPartOffsetLabel(part.name),
              onChanged: onOffset,
            ),
          ),
        ],
      ),
    );
  }
}

/// Champ d'adresse qui suit aussi les changements venus du contrôleur (adresse déduite du fichier).
class _OffsetField extends StatefulWidget {
  const _OffsetField({required this.value, required this.enabled, required this.label, required this.onChanged, this.helper});

  final String value;
  final bool enabled;
  final String label;
  final String? helper;
  final ValueChanged<String> onChanged;

  @override
  State<_OffsetField> createState() => _OffsetFieldState();
}

class _OffsetFieldState extends State<_OffsetField> {
  late final TextEditingController _text = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_OffsetField old) {
    super.didUpdateWidget(old);
    if (_text.text != widget.value) _text.text = widget.value;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _text,
      enabled: widget.enabled,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
