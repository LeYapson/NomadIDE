import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/dialogs.dart';
import '../../../l10n/l10n.dart';
import '../../editor/application/editor_controller.dart';
import '../../micropython/application/micropython_controller.dart';
import '../application/projects_controller.dart';
import '../data/project_store.dart';

enum _ProjectAction { create, rename, delete }

enum _EntryAction { rename, delete, upload }

/// Projets locaux : choix du projet, navigation dans ses dossiers, création,
/// renommage, suppression et envoi d'un fichier sur la carte.
class ProjectsPanel extends ConsumerWidget {
  const ProjectsPanel({super.key, this.onFileOpened});

  /// Appelé après l'ouverture d'un fichier (ex. pour refermer un tiroir).
  final VoidCallback? onFileOpened;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(projectsProvider);
    final controller = ref.read(projectsProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProjectHeader(state: state),
        if (state.current != null) ...[
          _PathBar(state: state),
          const Divider(height: 1),
          Expanded(
            child: state.entries.isEmpty
                ? Center(child: Text(state.directory.isEmpty ? l10n.prProjectEmpty : l10n.mpFolderEmpty))
                : ListView(
                    children: [
                      for (final entry in state.entries)
                        _EntryTile(entry: entry, project: state.current!, onFileOpened: onFileOpened),
                    ],
                  ),
          ),
        ] else
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.loaded ? l10n.prNoProjects : l10n.prLoading,
                      textAlign: TextAlign.center,
                    ),
                    if (state.loaded) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => _createProject(context, controller),
                        icon: const Icon(Icons.create_new_folder_outlined),
                        label: Text(l10n.prNewProject),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> _createProject(BuildContext context, ProjectsController controller) async {
  final l10n = context.l10n;
  final name = await showTextInputDialog(
    context,
    title: l10n.prNewProject,
    label: l10n.prProjectNameLabel,
    initialValue: l10n.prDefaultProjectName,
    confirmLabel: l10n.commonCreate,
  );
  if (name != null) await controller.createProject(name);
}

class _ProjectHeader extends ConsumerWidget {
  const _ProjectHeader({required this.state});

  final ProjectsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(projectsProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: state.projects.contains(state.current) ? state.current : null,
                hint: Text(l10n.prProjects),
                items: [for (final name in state.projects) DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis))],
                onChanged: (name) {
                  if (name != null) controller.selectProject(name);
                },
              ),
            ),
          ),
          PopupMenuButton<_ProjectAction>(
            tooltip: l10n.prProjectActions,
            onSelected: (action) async {
              switch (action) {
                case _ProjectAction.create:
                  await _createProject(context, controller);
                case _ProjectAction.rename:
                  final current = state.current;
                  if (current == null) return;
                  final name = await showTextInputDialog(
                    context,
                    title: l10n.prRenameProjectTitle,
                    label: l10n.mpNewName,
                    initialValue: current,
                    confirmLabel: l10n.commonRename,
                  );
                  if (name != null && name != current) await controller.renameProject(current, name);
                case _ProjectAction.delete:
                  final current = state.current;
                  if (current == null) return;
                  final confirmed = await showConfirmDialog(
                    context,
                    title: l10n.prDeleteProjectTitle,
                    message: l10n.prDeleteProjectMessage(current),
                    confirmLabel: l10n.commonDelete,
                    destructive: true,
                  );
                  if (confirmed) await controller.deleteProject(current);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: _ProjectAction.create, child: Text(l10n.prMenuNewProject)),
              PopupMenuItem(value: _ProjectAction.rename, enabled: state.current != null, child: Text(l10n.prMenuRenameProject)),
              PopupMenuItem(value: _ProjectAction.delete, enabled: state.current != null, child: Text(l10n.prMenuDeleteProject)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PathBar extends ConsumerWidget {
  const _PathBar({required this.state});

  final ProjectsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(projectsProvider.notifier);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: l10n.mpParentFolder,
            onPressed: state.directory.isEmpty ? null : controller.goUp,
            icon: const Icon(Icons.arrow_upward),
          ),
          Expanded(child: Text('/${state.directory}', overflow: TextOverflow.ellipsis)),
          IconButton(
            tooltip: l10n.mpNewFile,
            onPressed: () async {
              final name = await showTextInputDialog(
                context,
                title: l10n.mpNewFile,
                label: l10n.prFileNameLabel,
                initialValue: 'main.py',
                confirmLabel: l10n.commonCreate,
              );
              if (name == null) return;
              final path = await controller.createFile(name);
              if (path != null && state.current != null) {
                await ref.read(editorProvider.notifier).openLocalFile(state.current!, path, show: true);
              }
            },
            icon: const Icon(Icons.note_add_outlined),
          ),
          IconButton(
            tooltip: l10n.mpNewFolder,
            onPressed: () async {
              final name = await showTextInputDialog(
                context,
                title: l10n.mpNewFolder,
                label: l10n.prFolderNameLabel,
                confirmLabel: l10n.commonCreate,
              );
              if (name != null) await controller.createFolder(name);
            },
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.entry, required this.project, this.onFileOpened});

  final ProjectEntry entry;
  final String project;
  final VoidCallback? onFileOpened;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final controller = ref.read(projectsProvider.notifier);
    final board = ref.watch(microPythonProvider);
    final canUpload = !entry.isDirectory && board.isReady && !board.busy;

    return ListTile(
      dense: true,
      leading: Icon(entry.isDirectory ? Icons.folder_outlined : Icons.insert_drive_file_outlined),
      title: Text(entry.name, overflow: TextOverflow.ellipsis),
      subtitle: entry.isDirectory ? null : Text(_size(l10n, entry.size)),
      onTap: () async {
        if (entry.isDirectory) {
          await controller.openDirectory(entry.path);
        } else if (await ref.read(editorProvider.notifier).openLocalFile(project, entry.path, show: true)) {
          onFileOpened?.call();
        }
      },
      trailing: PopupMenuButton<_EntryAction>(
        tooltip: l10n.mpActions,
        onSelected: (action) async {
          switch (action) {
            case _EntryAction.rename:
              final name = await showTextInputDialog(
                context,
                title: l10n.commonRename,
                label: l10n.mpNewName,
                initialValue: entry.name,
                confirmLabel: l10n.commonRename,
              );
              if (name != null && name != entry.name) await controller.renameEntry(entry, name);
            case _EntryAction.delete:
              final confirmed = await showConfirmDialog(
                context,
                title: entry.isDirectory ? l10n.prDeleteFolderTitle : l10n.prDeleteFileTitle,
                message: entry.isDirectory ? l10n.prDeleteFolderMessage(entry.name) : l10n.prDeleteFileMessage(entry.name),
                confirmLabel: l10n.commonDelete,
                destructive: true,
              );
              if (confirmed) await controller.deleteEntry(entry);
            case _EntryAction.upload:
              await ref.read(microPythonProvider.notifier).uploadFromProject(project, entry.path);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: _EntryAction.rename, child: Text(l10n.mpMenuRename)),
          if (!entry.isDirectory)
            PopupMenuItem(
              value: _EntryAction.upload,
              enabled: canUpload,
              child: Text(board.isReady ? l10n.prMenuUpload : l10n.prMenuUploadDisconnected),
            ),
          PopupMenuItem(value: _EntryAction.delete, child: Text(l10n.mpMenuDelete)),
        ],
      ),
    );
  }

  static String _size(AppLocalizations l10n, int bytes) {
    if (bytes < 1024) return l10n.bytesB(bytes);
    if (bytes < 1024 * 1024) return l10n.bytesKb((bytes / 1024).toStringAsFixed(1));
    return l10n.bytesMb((bytes / 1024 / 1024).toStringAsFixed(1));
  }
}
