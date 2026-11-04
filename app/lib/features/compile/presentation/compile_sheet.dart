import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';

import '../../../app/providers.dart';
import '../../../app/settings.dart';
import '../../../l10n/l10n.dart';
import '../../flash/application/flash_controller.dart' show flashSizeLabel;
import '../../projects/application/projects_controller.dart';
import '../application/compile_controller.dart';
import '../data/project_archiver.dart';
import '../data/project_config.dart';
import 'compile_messages.dart';

/// Feuille de compilation cloud du projet courant.
Future<void> showCompileSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (_) => const CompileSheet(),
    );

class CompileSheet extends ConsumerStatefulWidget {
  const CompileSheet({super.key});

  @override
  ConsumerState<CompileSheet> createState() => _CompileSheetState();
}

class _CompileSheetState extends ConsumerState<CompileSheet> {
  CompileBoard? _board;

  @override
  void initState() {
    super.initState();
    _board = ref.read(compileProvider).board;
    if (_board == null) Future.microtask(_loadBoard);
  }

  Future<void> _loadBoard() async {
    final project = ref.read(projectsProvider).current;
    if (project == null) return;
    final store = await ref.read(projectStoreProvider.future);
    final config = await ProjectConfig.read(store, project);
    if (mounted && _board == null) setState(() => _board = config.board ?? CompileBoard.esp32);
  }

  Future<void> _compile(String project) async {
    final controller = ref.read(compileProvider.notifier);
    final board = _board ?? CompileBoard.esp32;
    final package = await controller.prepare(project);
    if (package == null || !mounted) return;

    final settings = ref.read(settingsProvider);
    if (settings.compileApprovedServer != settings.compileServerUrl) {
      final ok = await _confirmSend(package, settings.compileServerUrl);
      if (ok != true || !mounted) {
        controller.reset();
        return;
      }
      await ref.read(settingsProvider.notifier).approveCompileServer(settings.compileServerUrl);
    }
    await controller.start(package, board);
  }

  Future<bool?> _confirmSend(ProjectPackage package, String server) {
    final l10n = context.l10n;
    final host = Uri.tryParse(server)?.host ?? server;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.ccConsentTitle),
        content: Text(l10n.ccConsentBody(package.project, package.files.length, flashSizeLabel(l10n, package.rawBytes), host)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.ccConsentSend)),
        ],
      ),
    );
  }

  Future<void> _sendToFlash() async {
    final ok = await ref.read(compileProvider.notifier).sendToFlash();
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final project = ref.watch(projectsProvider).current;
    final compile = ref.watch(compileProvider);

    Widget body;
    if (project == null || !settings.compileConfigured) {
      body = _NeedSetup(
        onOpenSettings: () {
          ref.read(homeTabProvider.notifier).show(HomeTab.settings);
          Navigator.pop(context);
        },
      );
    } else {
      final host = Uri.tryParse(settings.compileServerUrl)?.host ?? settings.compileServerUrl;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cloud_upload_outlined),
            title: Text(l10n.ccProject(project)),
            subtitle: Text(host),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<CompileBoard>(
            initialValue: _board,
            decoration: InputDecoration(labelText: l10n.ccBoard, border: const OutlineInputBorder()),
            items: [for (final b in CompileBoard.values) DropdownMenuItem(value: b, child: Text(b.label))],
            onChanged: compile.working ? null : (b) => setState(() => _board = b),
          ),
          const SizedBox(height: 12),
          if (compile.working)
            OutlinedButton.icon(
              onPressed: ref.read(compileProvider.notifier).cancel,
              icon: const Icon(Icons.stop_circle_outlined),
              label: Text(l10n.ccCancel),
            )
          else
            FilledButton.icon(
              onPressed: _board == null ? null : () => _compile(project),
              icon: const Icon(Icons.build_outlined),
              label: Text(l10n.ccCompile),
            ),
          const SizedBox(height: 12),
          _Result(state: compile, onSendToFlash: _sendToFlash),
        ],
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(header: true, child: Text(l10n.ccTitle, style: theme.textTheme.titleLarge)),
            const SizedBox(height: 12),
            body,
          ],
        ),
      ),
    );
  }
}

class _NeedSetup extends StatelessWidget {
  const _NeedSetup({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.cloud_off_outlined),
          title: Text(l10n.ccNeedSetupTitle),
          subtitle: Text(l10n.ccNeedSetupBody),
        ),
        FilledButton.icon(onPressed: onOpenSettings, icon: const Icon(Icons.settings_outlined), label: Text(l10n.ccOpenSettings)),
      ],
    );
  }
}

class _Result extends ConsumerWidget {
  const _Result({required this.state, required this.onSendToFlash});

  final CompileState state;
  final VoidCallback onSendToFlash;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final status = state.status;
    final children = <Widget>[];

    String? statusText;
    IconData? icon;
    Color? color;
    switch (state.phase) {
      case CompilePhase.idle:
        break;
      case CompilePhase.packaging:
        statusText = l10n.ccPhasePackaging;
      case CompilePhase.uploading:
        statusText = l10n.ccPhaseUploading;
      case CompilePhase.queued:
        statusText = l10n.ccPhaseQueued((status?.queuePosition ?? 0) + 1);
      case CompilePhase.running:
        statusText = l10n.ccPhaseRunning;
      case CompilePhase.succeeded:
        statusText = l10n.ccSucceeded(((status?.durationMs ?? 0) / 1000).round());
        icon = Icons.check_circle_outline;
        color = theme.colorScheme.primary;
      case CompilePhase.failed:
        statusText = l10n.ccFailed;
        icon = Icons.error_outline;
        color = theme.colorScheme.error;
      case CompilePhase.cancelled:
        statusText = l10n.ccCancelled;
        icon = Icons.cancel_outlined;
    }

    if (state.working) children.add(const LinearProgressIndicator());
    if (statusText != null) {
      children.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Semantics(
          liveRegion: true,
          child: Row(
            children: [
              if (icon != null) ...[Icon(icon, color: color), const SizedBox(width: 8)],
              Expanded(child: Text(statusText, style: theme.textTheme.titleMedium?.copyWith(color: color))),
            ],
          ),
        ),
      ));
    }

    final problem = state.problem;
    if (problem != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Semantics(liveRegion: true, child: Text(compileProblemMessage(l10n, problem, state.detail), style: TextStyle(color: theme.colorScheme.error))),
      ));
    } else if (state.phase == CompilePhase.failed && state.detail != null) {
      // Échec qui ne vient pas du code (délai dépassé, aucun binaire) : le service l'explique.
      children.add(Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(state.detail!)));
    }

    if (state.phase == CompilePhase.succeeded && state.flashable != null) {
      children.add(FilledButton.icon(onPressed: onSendToFlash, icon: const Icon(Icons.flash_on_outlined), label: Text(l10n.ccFlash)));
    }

    final diagnostics = [...state.errors, ...state.warnings];
    if (diagnostics.isNotEmpty) {
      children
        ..add(const SizedBox(height: 8))
        ..add(Semantics(
          header: true,
          child: Text(
            '${l10n.ccDiagnostics} · ${l10n.ccErrorCount(state.errors.length)} · ${l10n.ccWarningCount(state.warnings.length)}',
            style: theme.textTheme.titleSmall,
          ),
        ))
        ..addAll([
          for (final d in diagnostics)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                d.severity == DiagnosticSeverity.error ? Icons.error_outline : Icons.warning_amber_outlined,
                color: d.severity == DiagnosticSeverity.error ? theme.colorScheme.error : null,
              ),
              title: Text(d.message),
              subtitle: Text('${d.file}:${d.line}${d.column == null ? '' : ':${d.column}'}'),
              onTap: () async {
                await ref.read(compileProvider.notifier).openDiagnostic(d);
                if (context.mounted) Navigator.pop(context);
              },
              key: ValueKey('${d.file}:${d.line}:${d.message}'),
            ),
        ]);
    }

    if (status != null && status.log.trim().isNotEmpty) {
      children.add(ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(l10n.ccLog),
        children: [
          Container(
            constraints: const BoxConstraints(maxHeight: 260),
            width: double.infinity,
            child: SingleChildScrollView(
              child: SelectableText(status.log, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ),
          ),
        ],
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}
