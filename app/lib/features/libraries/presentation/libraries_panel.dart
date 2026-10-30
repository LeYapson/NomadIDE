import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_protocols/nomad_protocols.dart' show RemoteEntry;

import '../../../app/dialogs.dart';
import '../../../l10n/l10n.dart';
import '../../../ui/ui.dart';
import '../../micropython/application/micropython_controller.dart';
import '../application/libraries_controller.dart';
import '../data/mip_client.dart';

/// Onglet « Bibliothèques » de la page MicroPython : chercher un pilote (écran, capteur…), l'installer
/// sur la carte en un toucher, voir et supprimer ce qui est installé.
class LibrariesPanel extends ConsumerStatefulWidget {
  const LibrariesPanel({super.key});

  @override
  ConsumerState<LibrariesPanel> createState() => _LibrariesPanelState();
}

class _LibrariesPanelState extends ConsumerState<LibrariesPanel> {
  late final TextEditingController _search = TextEditingController(text: ref.read(librariesProvider).query);
  final TextEditingController _address = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final libraries = ref.read(librariesProvider.notifier);
      if (ref.read(librariesProvider).status == LibIndexStatus.idle) libraries.loadIndex();
      libraries.refreshInstalled();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(librariesProvider);
    final controller = ref.read(librariesProvider.notifier);
    final ready = ref.watch(microPythonProvider.select((s) => s.isReady));
    final boardBusy = ref.watch(microPythonProvider.select((s) => s.busy));
    final textTheme = Theme.of(context).textTheme;
    final canInstall = ready && !boardBusy && !state.working;

    // Carte connectée : on lit ce qui est déjà installé.
    ref.listen(microPythonProvider.select((s) => s.isReady), (_, isReady) {
      if (isReady) controller.refreshInstalled();
    });

    final results = state.results;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (!ready) ...[
          StatusBanner(message: l10n.libConnectFirst, kind: StatusKind.info),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _search,
          onChanged: controller.setQuery,
          decoration: InputDecoration(
            labelText: l10n.libSearchLabel,
            hintText: l10n.libSearchHint,
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        if (state.working) ...[
          ProgressStatus(
            label: state.phase == LibPhase.downloading
                ? l10n.libDownloading(state.busyName ?? '')
                : l10n.libWriting((state.fileDone + 1).clamp(1, state.fileTotal == 0 ? 1 : state.fileTotal), state.fileTotal),
            value: state.phase == LibPhase.writing && state.fileTotal > 0 ? state.fileDone / state.fileTotal : null,
          ),
          const SizedBox(height: 8),
        ],
        if (state.message != null && !state.working) ...[
          StatusBanner(message: state.message!, kind: state.succeeded ? StatusKind.success : StatusKind.error),
          const SizedBox(height: 8),
        ],
        switch (state.status) {
          LibIndexStatus.idle || LibIndexStatus.loading => ProgressStatus(label: l10n.libLoading),
          LibIndexStatus.failed => Wrap(
              children: [
                OutlinedButton.icon(onPressed: controller.loadIndex, icon: const Icon(Icons.refresh), label: Text(l10n.libRetry)),
              ],
            ),
          LibIndexStatus.ready => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.offline) ...[
                  StatusBanner(message: l10n.libOffline, kind: StatusKind.info),
                  const SizedBox(height: 8),
                ],
                if (results.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(l10n.libNoResult(state.query.trim())),
                  ),
                for (final package in results)
                  _PackageTile(
                    package: package,
                    enabled: canInstall,
                    installing: state.busyName == package.name,
                    onInstall: () => controller.install(package.name),
                  ),
              ],
            ),
        },
        Disclosure(
          title: l10n.libGithubTitle,
          initiallyExpanded: state.status == LibIndexStatus.ready && results.isEmpty,
          children: [
            const SizedBox(height: 4),
            TextField(
              controller: _address,
              decoration: InputDecoration(
                labelText: l10n.libGithubLabel,
                helperText: l10n.libGithubHelper,
                helperMaxLines: 2,
                hintText: 'github:auteur/depot',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              children: [
                FilledButton.tonalIcon(
                  onPressed: canInstall ? () => controller.install(_address.text) : null,
                  icon: const Icon(Icons.download),
                  label: Text(l10n.libInstall),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: Semantics(header: true, child: Text(l10n.libInstalledTitle, style: textTheme.titleMedium))),
            IconButton(
              tooltip: l10n.libRefreshInstalled,
              onPressed: ready && !boardBusy ? controller.refreshInstalled : null,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (state.installed != null && state.installed!.isEmpty) Text(l10n.libInstalledEmpty),
        for (final entry in state.installed ?? const <RemoteEntry>[])
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(entry.isDirectory ? Icons.folder_outlined : Icons.description_outlined),
            title: Text(entry.name),
            trailing: IconButton(
              tooltip: l10n.libRemoveTooltip(entry.name),
              onPressed: ready && !boardBusy && !state.working ? () => _confirmRemove(entry) : null,
              icon: const Icon(Icons.delete_outline),
            ),
          ),
        const SizedBox(height: 12),
        Text(l10n.libSourceNote, style: textTheme.bodySmall),
      ],
    );
  }

  Future<void> _confirmRemove(RemoteEntry entry) async {
    final l10n = context.l10n;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.libRemoveConfirmTitle(entry.name),
      message: l10n.libRemoveConfirmBody(entry.name),
      confirmLabel: l10n.commonDelete,
      destructive: true,
    );
    if (confirmed) await ref.read(librariesProvider.notifier).remove(entry);
  }
}

/// Une bibliothèque de l'index : nom, description, version et licence, bouton d'installation (48 dp).
class _PackageTile extends StatelessWidget {
  const _PackageTile({required this.package, required this.enabled, required this.installing, required this.onInstall});

  final MipPackage package;
  final bool enabled;
  final bool installing;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(package.name, style: textTheme.titleSmall),
                  if (package.description.isNotEmpty) Text(package.description),
                  Text(
                    l10n.libVersionLicense(package.version, package.license.isEmpty ? l10n.libNoLicense : package.license),
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: l10n.libInstallTooltip(package.name),
              child: FilledButton.tonal(
                onPressed: enabled ? onInstall : null,
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                child: installing
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l10n.libInstall),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
