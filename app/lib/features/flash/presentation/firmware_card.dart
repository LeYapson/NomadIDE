import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../../../ui/ui.dart';
import '../application/firmware_controller.dart';
import '../application/flash_controller.dart' show PickedFile;
import '../data/firmware_catalog.dart';

/// « Firmware MicroPython officiel » : choisir sa carte, voir la dernière version et l'adresse exacte
/// du téléchargement, puis le télécharger en un clic. Le fichier est remis à [onFile], qui le traite
/// comme un fichier choisi à la main. Section repliable : c'est une autre façon d'obtenir le fichier de
/// l'étape 1, pas une étape en plus.
class FirmwareCard extends ConsumerWidget {
  const FirmwareCard({
    super.key,
    required this.boards,
    required this.onFile,
    required this.enabled,
    this.initiallyExpanded = true,
  });

  /// Cartes proposées (celles que l'écran de flash courant sait écrire).
  final List<FirmwareBoard> boards;
  final void Function(PickedFile file) onFile;

  /// Faux pendant qu'un flash est en cours.
  final bool enabled;

  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(firmwareProvider);
    final controller = ref.read(firmwareProvider.notifier);
    final board = boards.contains(state.board) ? state.board! : boards.first;
    final release = state.release != null && state.release!.board == board ? state.release : null;
    final idle = enabled && !state.busy;

    return Disclosure(
      title: l10n.fwTitle,
      initiallyExpanded: initiallyExpanded,
      children: [
        Text(l10n.fwHint, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        DropdownButtonFormField<FirmwareBoard>(
          key: ValueKey(board),
          initialValue: board,
          isExpanded: true,
          decoration: InputDecoration(labelText: l10n.fwBoardLabel, border: const OutlineInputBorder()),
          items: [for (final b in boards) DropdownMenuItem(value: b, child: Text(b.label))],
          onChanged: idle ? controller.selectBoard : null,
        ),
        const SizedBox(height: 8),
        Wrap(
          children: [
            OutlinedButton.icon(
              onPressed: idle ? () => controller.find(board) : null,
              icon: const Icon(Icons.search),
              label: Text(l10n.fwFind),
            ),
          ],
        ),
        if (state.phase == FirmwarePhase.searching) ...[
          const SizedBox(height: 12),
          ProgressStatus(label: l10n.fwSearching),
        ],
        if (release != null && state.phase != FirmwarePhase.searching) ...[
          const SizedBox(height: 12),
          Text(l10n.fwFound(release.version, release.board.label), style: Theme.of(context).textTheme.titleSmall),
          if (release.date != null) Text(l10n.fwDate(_formatDate(release.date!))),
          const SizedBox(height: 4),
          Text(l10n.fwSource(release.url.host), style: Theme.of(context).textTheme.bodySmall),
          SelectableText(release.url.toString(), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            children: [
              FilledButton.tonalIcon(
                onPressed: idle
                    ? () async {
                        final file = await controller.download();
                        if (file != null) onFile(file);
                      }
                    : null,
                icon: const Icon(Icons.download),
                label: Text(l10n.fwDownload),
              ),
            ],
          ),
        ],
        if (state.phase == FirmwarePhase.downloading) ...[
          const SizedBox(height: 12),
          ProgressStatus(
            label: state.fraction == null ? l10n.fwDownloadingUnknown : l10n.fwDownloading((state.fraction! * 100).round()),
            spokenLabel: state.fraction == null
                ? l10n.fwDownloadingUnknown
                : l10n.fwDownloading(announcedPercent(state.fraction)),
            value: state.fraction,
          ),
        ],
        if (state.message != null && state.phase != FirmwarePhase.searching && state.phase != FirmwarePhase.downloading) ...[
          const SizedBox(height: 12),
          StatusBanner(
            message: state.message!,
            kind: state.phase == FirmwarePhase.downloaded ? StatusKind.success : StatusKind.error,
          ),
        ],
      ],
    );
  }

  /// AAAAMMJJ → AAAA-MM-JJ.
  static String _formatDate(String yyyymmdd) =>
      yyyymmdd.length == 8 ? '${yyyymmdd.substring(0, 4)}-${yyyymmdd.substring(4, 6)}-${yyyymmdd.substring(6)}' : yyyymmdd;
}
