import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_editor/nomad_editor.dart';

import '../../../app/dialogs.dart';
import '../../../app/providers.dart';
import '../../micropython/application/micropython_controller.dart';
import '../../micropython/presentation/widgets/repl_log_view.dart';
import '../../projects/application/projects_controller.dart';
import '../../projects/data/storage_exception.dart';
import '../../projects/presentation/project_dialogs.dart';
import '../../projects/presentation/projects_panel.dart';
import '../../../l10n/error_messages.dart';
import '../../../l10n/l10n.dart';
import '../application/editor_controller.dart';

enum _CloseChoice { save, discard, cancel }

/// Éditeur de code : projets locaux, onglets de fichiers, coloration, enregistrement
/// sur l'appareil, envoi et exécution sur la carte, barre de symboles sur mobile.
class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({super.key});

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  static const double _wideBreakpoint = 840;

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _showOutput = false;
  bool _restoreDialogOpen = false;

  /// Écran tactile : la barre de symboles remplace les touches absentes du clavier.
  static bool get _isMobile => defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    // Les brouillons peuvent être déjà chargés quand la page apparaît.
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerDrafts());
  }

  // ---------------------------------------------------------------------------
  // Brouillons
  // ---------------------------------------------------------------------------

  Future<void> _offerDrafts() async {
    if (!mounted || _restoreDialogOpen) return;
    final drafts = ref.read(editorProvider).pendingDrafts;
    if (drafts.isEmpty) return;
    _restoreDialogOpen = true;
    final restore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.edDraftsTitle),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.edDraftsIntro),
              const SizedBox(height: 8),
              for (final draft in drafts)
                Text(
                  draft.project != null
                      ? context.l10n.edDraftItemProject(draft.name, draft.project!)
                      : context.l10n.edDraftItem(draft.name),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.edDraftsDiscard)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.l10n.edDraftsRestore)),
        ],
      ),
    );
    _restoreDialogOpen = false;
    final editor = ref.read(editorProvider.notifier);
    if (restore ?? false) {
      await editor.restoreDrafts();
      if (mounted) ref.read(homeTabProvider.notifier).show(HomeTab.editor);
    } else {
      await editor.discardDrafts();
    }
  }

  // ---------------------------------------------------------------------------
  // Enregistrement
  // ---------------------------------------------------------------------------

  /// Enregistre sur l'appareil ; demande l'emplacement si le fichier n'en a pas encore.
  Future<bool> _save(EditorDocument document) async {
    if (document.hasLocalTarget) return ref.read(editorProvider.notifier).saveLocal(document);
    return _saveAs(document);
  }

  Future<bool> _saveAs(EditorDocument document) async {
    final projects = ref.read(projectsProvider);
    final target = await showSaveAsDialog(
      context,
      projects: projects.projects,
      currentProject: projects.current,
      initialPath: document.name,
    );
    if (target == null || !mounted) return false;

    final projectsController = ref.read(projectsProvider.notifier);
    if (target.isNewProject) {
      if (await projectsController.createProject(target.project) == null) return false;
    } else if (!document.isLocal(target.project, target.path)) {
      try {
        final store = await ref.read(projectStoreProvider.future);
        if (await store.exists(target.project, target.path)) {
          if (!mounted) return false;
          final replace = await showConfirmDialog(
            context,
            title: context.l10n.mpReplaceFileTitle,
            message: context.l10n.edReplaceFileMessage(target.path, target.project),
            confirmLabel: context.l10n.commonReplace,
            destructive: true,
          );
          if (!replace) return false;
        }
      } on StorageException catch (e) {
        projectsController.reportError(e);
        return false;
      }
    }
    return ref.read(editorProvider.notifier).saveLocal(document, project: target.project, path: target.path);
  }

  Future<void> _sendToBoard(EditorDocument document) async {
    var path = document.boardPath;
    if (path == null) {
      final suggestion = ref.read(microPythonProvider.notifier).pathOf(document.name);
      path = await showTextInputDialog(
        context,
        title: context.l10n.edSendTitle,
        label: context.l10n.edSendPathLabel,
        initialValue: suggestion,
        confirmLabel: context.l10n.edSend,
        helper: context.l10n.edSendHelper,
      );
      if (path == null) return;
      if (!path.startsWith('/')) path = '/$path';
    }
    if (!mounted) return;
    final sent = await ref.read(editorProvider.notifier).saveToBoard(document, path: path);
    if (sent && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.edSentSnack(path!))));
    }
  }

  Future<void> _run(EditorDocument document) async {
    setState(() => _showOutput = true);
    await ref.read(editorProvider.notifier).run(document);
  }

  Future<void> _close(EditorDocument document) async {
    final editor = ref.read(editorProvider.notifier);
    if (!document.dirty) {
      editor.close(document);
      return;
    }
    final choice = await showDialog<_CloseChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.edCloseTitle(document.name)),
        content: Text(context.l10n.edCloseBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, _CloseChoice.cancel), child: Text(context.l10n.commonCancel)),
          TextButton(onPressed: () => Navigator.pop(context, _CloseChoice.discard), child: Text(context.l10n.edDontSave)),
          FilledButton(onPressed: () => Navigator.pop(context, _CloseChoice.save), child: Text(context.l10n.commonSave)),
        ],
      ),
    );
    switch (choice ?? _CloseChoice.cancel) {
      case _CloseChoice.cancel:
        return;
      case _CloseChoice.discard:
        editor.close(document);
      case _CloseChoice.save:
        // Un fichier dont l'enregistrement échoue reste ouvert : rien n'est perdu.
        if (await _save(document) && mounted) editor.close(document);
    }
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(editorProvider);
    final micro = ref.watch(microPythonProvider);
    final controller = ref.read(editorProvider.notifier);
    final document = editor.active;
    final wide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;

    ref.listen(editorProvider.select((s) => s.pendingDrafts.length), (_, count) {
      if (count > 0) _offerDrafts();
    });
    ref.listen(projectsProvider.select((s) => s.error), (_, error) {
      if (error == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(storageErrorMessage(context.l10n, error))));
      ref.read(projectsProvider.notifier).clearError();
    });

    final body = SafeArea(
      child: document == null
          ? _EmptyState(onNew: controller.newDocument)
          : Column(
              children: [
                _DocumentTabs(editor: editor, onClose: _close),
                const Divider(height: 1),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final output = _showOutput ? const ReplLogView() : null;
                      final surface = KeyedSubtree(
                        key: ValueKey(document.id),
                        child: NomadCodeEditor(controller: document.controller),
                      );
                      // Écran large ou paysage : éditeur et sortie côte à côte.
                      if (constraints.maxWidth >= _wideBreakpoint - 280) {
                        return Row(
                          children: [
                            Expanded(flex: 3, child: surface),
                            if (output != null) ...[
                              const VerticalDivider(width: 1),
                              Expanded(flex: 2, child: output),
                            ],
                          ],
                        );
                      }
                      return Column(
                        children: [
                          Expanded(child: surface),
                          if (output != null) ...[
                            const Divider(height: 1),
                            SizedBox(height: (constraints.maxHeight * 0.35).clamp(120.0, 260.0), child: output),
                          ],
                        ],
                      );
                    },
                  ),
                ),
                if (_isMobile) SymbolBar(controller: document.controller),
              ],
            ),
    );

    return CallbackShortcuts(
      bindings: {
        // Ctrl+S (Cmd+S sur macOS) : enregistrer sur l'appareil.
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (document != null) _save(document);
        },
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
          if (document != null) _save(document);
        },
      },
      child: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: Text(context.l10n.edTitle),
          actions: [
            IconButton(
              tooltip: context.l10n.mpNewFile,
              onPressed: controller.newDocument,
              icon: const Icon(Icons.note_add_outlined),
            ),
            if (document != null) ...[
              ListenableBuilder(
                listenable: document.controller,
                builder: (context, _) => IconButton(
                  tooltip: context.l10n.edSaveTooltip,
                  onPressed: () => _save(document),
                  icon: Icon(document.dirty ? Icons.save : Icons.save_outlined),
                ),
              ),
              IconButton(
                tooltip: micro.isReady ? context.l10n.edSendTooltip : context.l10n.edConnectBoardHint,
                onPressed: micro.isReady && !micro.busy ? () => _sendToBoard(document) : null,
                icon: const Icon(Icons.upload_file),
              ),
              if (micro.busy)
                IconButton(
                  tooltip: context.l10n.mpStop,
                  color: Theme.of(context).colorScheme.error,
                  onPressed: ref.read(microPythonProvider.notifier).stop,
                  icon: const Icon(Icons.stop_circle_outlined),
                )
              else
                IconButton(
                  tooltip: micro.isReady ? context.l10n.edRunTooltip : context.l10n.edConnectBoardHint,
                  onPressed: micro.isReady ? () => _run(document) : null,
                  icon: const Icon(Icons.play_arrow),
                ),
            ],
            IconButton(
              tooltip: _showOutput ? context.l10n.edHideOutput : context.l10n.edShowOutput,
              onPressed: () => setState(() => _showOutput = !_showOutput),
              icon: Icon(_showOutput ? Icons.terminal : Icons.terminal_outlined),
            ),
          ],
        ),
        drawer: wide
            ? null
            : Drawer(
                child: SafeArea(
                  child: ProjectsPanel(onFileOpened: () => _scaffoldKey.currentState?.closeDrawer()),
                ),
              ),
        body: wide
            ? Row(
                children: [
                  const SizedBox(width: 280, child: ProjectsPanel()),
                  const VerticalDivider(width: 1),
                  Expanded(child: body),
                ],
              )
            : body,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onNew});

  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(context.l10n.edEmptyTitle, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(context.l10n.edEmptyBody, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onNew,
              icon: const Icon(Icons.note_add_outlined),
              label: Text(context.l10n.mpNewFile),
            ),
          ],
        ),
      ),
    );
  }
}

class _DocumentTabs extends ConsumerWidget {
  const _DocumentTabs({required this.editor, required this.onClose});

  final EditorState editor;
  final void Function(EditorDocument document) onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(editorProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: editor.documents.length,
        itemBuilder: (context, i) {
          final document = editor.documents[i];
          final selected = i == editor.activeIndex;
          return ListenableBuilder(
            listenable: document.controller,
            builder: (context, _) => InkWell(
              onTap: () => controller.select(i),
              child: Container(
                padding: const EdgeInsets.only(left: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: selected ? scheme.primary : Colors.transparent, width: 2)),
                ),
                child: Row(
                  children: [
                    Text(
                      '${document.dirty ? '● ' : ''}${document.name}',
                      style: TextStyle(fontWeight: selected ? FontWeight.w600 : FontWeight.normal),
                    ),
                    IconButton(
                      tooltip: context.l10n.commonClose,
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onClose(document),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
