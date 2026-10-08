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
import '../../projects/presentation/storage_messages.dart';
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
        title: const Text('Reprendre le travail non enregistré ?'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('L\'application s\'est fermée avant l\'enregistrement de ces fichiers :'),
              const SizedBox(height: 8),
              for (final draft in drafts)
                Text('• ${draft.name}${draft.project != null ? '  (${draft.project})' : ''}', overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abandonner')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restaurer')),
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
            title: 'Remplacer le fichier ?',
            message: '« ${target.path} » existe déjà dans le projet « ${target.project} ». Son contenu sera remplacé.',
            confirmLabel: 'Remplacer',
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
        title: 'Envoyer sur la carte',
        label: 'Chemin sur la carte',
        initialValue: suggestion,
        confirmLabel: 'Envoyer',
        helper: 'Ex. /main.py (lancé au démarrage de la carte)',
      );
      if (path == null) return;
      if (!path.startsWith('/')) path = '/$path';
    }
    if (!mounted) return;
    final sent = await ref.read(editorProvider.notifier).saveToBoard(document, path: path);
    if (sent && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Envoyé sur la carte : $path (CRC32 vérifié)')));
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
        title: Text('Enregistrer « ${document.name} » ?'),
        content: const Text('Ce fichier a des modifications non enregistrées.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, _CloseChoice.cancel), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, _CloseChoice.discard), child: const Text('Ne pas enregistrer')),
          FilledButton(onPressed: () => Navigator.pop(context, _CloseChoice.save), child: const Text('Enregistrer')),
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
        ..showSnackBar(SnackBar(content: Text(storageErrorMessage(error))));
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
          title: const Text('NomadMCU · Éditeur'),
          actions: [
            IconButton(
              tooltip: 'Nouveau fichier',
              onPressed: controller.newDocument,
              icon: const Icon(Icons.note_add_outlined),
            ),
            if (document != null) ...[
              ListenableBuilder(
                listenable: document.controller,
                builder: (context, _) => IconButton(
                  tooltip: 'Enregistrer sur l\'appareil (Ctrl+S)',
                  onPressed: () => _save(document),
                  icon: Icon(document.dirty ? Icons.save : Icons.save_outlined),
                ),
              ),
              IconButton(
                tooltip: micro.isReady ? 'Envoyer sur la carte' : 'Connectez une carte (onglet MicroPython)',
                onPressed: micro.isReady && !micro.busy ? () => _sendToBoard(document) : null,
                icon: const Icon(Icons.upload_file),
              ),
              if (micro.busy)
                IconButton(
                  tooltip: 'Arrêter',
                  color: Theme.of(context).colorScheme.error,
                  onPressed: ref.read(microPythonProvider.notifier).stop,
                  icon: const Icon(Icons.stop_circle_outlined),
                )
              else
                IconButton(
                  tooltip: micro.isReady
                      ? 'Exécuter la sélection ou le fichier sur la carte (sans enregistrer)'
                      : 'Connectez une carte (onglet MicroPython)',
                  onPressed: micro.isReady ? () => _run(document) : null,
                  icon: const Icon(Icons.play_arrow),
                ),
            ],
            IconButton(
              tooltip: _showOutput ? 'Masquer la sortie' : 'Afficher la sortie',
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
            const Text('Aucun fichier ouvert.', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text(
              'Créez un fichier, ouvrez-en un depuis vos projets (menu en haut à gauche), '
              'ou touchez un fichier de la carte dans l\'onglet MicroPython.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onNew, icon: const Icon(Icons.note_add_outlined), label: const Text('Nouveau fichier')),
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
                      tooltip: 'Fermer',
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
