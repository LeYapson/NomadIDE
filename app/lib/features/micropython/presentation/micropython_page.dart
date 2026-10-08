import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_protocols/nomad_protocols.dart';

import '../../../app/dialogs.dart';
import '../../../l10n/l10n.dart';
import '../../editor/application/editor_controller.dart';
import '../../projects/application/projects_controller.dart';
import '../../projects/presentation/project_dialogs.dart';
import '../application/micropython_controller.dart';
import 'widgets/console_panel.dart';

/// Page de validation du raw REPL et du système de fichiers MicroPython.
class MicroPythonPage extends ConsumerWidget {
  const MicroPythonPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<String?>(microPythonProvider.select((s) => s.errorMessage), (previous, next) {
      if (next != null && next != previous) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(next)));
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.mpTitle)),
      body: SafeArea(
        child: Column(
          children: [
            const _Toolbar(),
            const Divider(height: 1),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth >= 720) {
                    return const Row(
                      children: [
                        SizedBox(width: 320, child: _FilesPanel()),
                        VerticalDivider(width: 1),
                        Expanded(child: ConsolePanel()),
                      ],
                    );
                  }
                  return DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        TabBar(tabs: [Tab(text: context.l10n.mpTabConsole), Tab(text: context.l10n.mpTabFiles)]),
                        const Expanded(child: TabBarView(children: [ConsolePanel(), _FilesPanel()])),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(microPythonProvider);
    final controller = ref.read(microPythonProvider.notifier);
    final idle = state.status == ReplStatus.disconnected;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: (MediaQuery.sizeOf(context).width - 32).clamp(200.0, 380.0).toDouble(),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: l10n.monBoardLabel,
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<SerialDeviceInfo>(
                  isDense: true,
                  isExpanded: true,
                  value: state.devices.contains(state.selectedDevice) ? state.selectedDevice : null,
                  hint: Text(state.devices.isEmpty ? l10n.monNoBoardDetected : l10n.monChooseBoard),
                  items: [
                    for (final d in state.devices)
                      DropdownMenuItem(
                        value: d,
                        child: Text('${d.displayName}  ${d.details}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: idle
                      ? (d) {
                          if (d != null) controller.selectDevice(d);
                        }
                      : null,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.monRefreshList,
            onPressed: idle ? controller.refreshDevices : null,
            icon: const Icon(Icons.refresh),
          ),
          switch (state.status) {
            ReplStatus.disconnected => FilledButton.icon(
                onPressed: state.selectedDevice == null ? null : controller.connect,
                icon: const Icon(Icons.usb),
                label: Text(l10n.mpConnectRawRepl),
              ),
            ReplStatus.connecting => FilledButton(onPressed: null, child: Text(l10n.monConnecting)),
            ReplStatus.ready => FilledButton.tonalIcon(
                onPressed: state.busy ? null : controller.disconnect,
                icon: const Icon(Icons.usb_off),
                label: Text(l10n.monDisconnect),
              ),
          },
          if (state.busy) const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Console
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// Fichiers
// -----------------------------------------------------------------------------

enum _BoardAction { rename, download, delete }

class _TransferBar extends StatelessWidget {
  const _TransferBar({required this.transfer});

  final TransferProgress transfer;

  @override
  Widget build(BuildContext context) {
    final arrow = transfer.direction == TransferDirection.upload ? '↑' : '↓';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.mpTransferLine(arrow, transfer.name, transfer.done, transfer.total),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: transfer.fraction),
        ],
      ),
    );
  }
}

class _FilesPanel extends ConsumerWidget {
  const _FilesPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(microPythonProvider);
    final controller = ref.read(microPythonProvider.notifier);
    final enabled = state.isReady && !state.busy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: l10n.mpParentFolder,
                onPressed: enabled && state.cwd != '/' ? controller.goUp : null,
                icon: const Icon(Icons.arrow_upward),
              ),
              Expanded(child: Text(state.cwd, overflow: TextOverflow.ellipsis)),
              IconButton(
                tooltip: l10n.mpRefresh,
                onPressed: enabled ? controller.refreshFiles : null,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: l10n.mpNewFile,
                onPressed: enabled ? () => _newFile(context, controller) : null,
                icon: const Icon(Icons.note_add_outlined),
              ),
              IconButton(
                tooltip: l10n.mpNewFolder,
                onPressed: enabled ? () => _newFolder(context, controller) : null,
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
              IconButton(
                tooltip: l10n.mpUploadFromProject,
                onPressed: enabled ? () => _upload(context, ref, state, controller) : null,
                icon: const Icon(Icons.upload_file),
              ),
              IconButton(
                tooltip: l10n.mpSelfTest,
                onPressed: enabled ? controller.runTransferSelfTest : null,
                icon: const Icon(Icons.speed),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (state.transfer != null) _TransferBar(transfer: state.transfer!),
        Expanded(
          child: state.files.isEmpty
              ? Center(child: Text(state.isReady ? l10n.mpFolderEmpty : l10n.mpNotConnected))
              : ListView(
                  children: [
                    for (final e in state.files)
                      ListTile(
                        dense: true,
                        enabled: enabled,
                        leading: Icon(e.isDirectory ? Icons.folder_outlined : Icons.insert_drive_file_outlined),
                        title: Text(e.name),
                        subtitle: e.isDirectory || e.size == null ? null : Text(l10n.bytesB(e.size!)),
                        onTap: () => e.isDirectory ? controller.openDirectory(e.name) : _view(context, ref, controller, e),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!e.isDirectory && e.name.endsWith('.py'))
                              IconButton(
                                tooltip: l10n.mpRunFile,
                                icon: const Icon(Icons.play_arrow),
                                onPressed: enabled ? () => controller.runFile(e.name) : null,
                              ),
                            PopupMenuButton<_BoardAction>(
                              tooltip: l10n.mpActions,
                              enabled: enabled,
                              onSelected: (action) => _onAction(context, ref, controller, e, action),
                              itemBuilder: (context) => [
                                PopupMenuItem(value: _BoardAction.rename, child: Text(l10n.mpMenuRename)),
                                if (!e.isDirectory)
                                  PopupMenuItem(value: _BoardAction.download, child: Text(l10n.mpMenuDownload)),
                                PopupMenuItem(value: _BoardAction.delete, child: Text(l10n.mpMenuDelete)),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _onAction(
    BuildContext context,
    WidgetRef ref,
    MicroPythonController controller,
    RemoteEntry entry,
    _BoardAction action,
  ) async {
    switch (action) {
      case _BoardAction.rename:
        final name = await showTextInputDialog(
          context,
          title: context.l10n.mpRenameOnBoardTitle,
          label: context.l10n.mpNewName,
          initialValue: entry.name,
          confirmLabel: context.l10n.commonRename,
          cancelLabel: context.l10n.commonCancel,
        );
        if (name != null && name != entry.name) await controller.renameEntry(entry, name);
      case _BoardAction.download:
        await _download(context, ref, controller, entry);
      case _BoardAction.delete:
        await _confirmDelete(context, controller, entry);
    }
  }

  Future<void> _upload(BuildContext context, WidgetRef ref, MicroPythonState state, MicroPythonController controller) async {
    final picked = await showProjectFilePicker(context);
    if (picked == null || !context.mounted) return;
    final name = picked.path.split('/').last;
    if (state.files.any((f) => f.name == name)) {
      final replace = await showConfirmDialog(
        context,
        title: context.l10n.mpReplaceFileTitle,
        message: context.l10n.mpReplaceFileMessage(name, state.cwd),
        confirmLabel: context.l10n.commonReplace,
        cancelLabel: context.l10n.commonCancel,
        destructive: true,
      );
      if (!replace) return;
    }
    await controller.uploadFromProject(picked.project, picked.path);
  }

  Future<void> _download(BuildContext context, WidgetRef ref, MicroPythonController controller, RemoteEntry entry) async {
    final projects = ref.read(projectsProvider);
    final target = await showSaveAsDialog(
      context,
      projects: projects.projects,
      currentProject: projects.current,
      initialPath: entry.name,
      title: context.l10n.mpDownloadTitle,
      confirmLabel: context.l10n.mpDownload,
    );
    if (target == null) return;
    final projectsController = ref.read(projectsProvider.notifier);
    if (target.isNewProject && await projectsController.createProject(target.project) == null) return;
    final saved = await controller.downloadToProject(entry, target.project, target.path);
    if (saved) await projectsController.refresh();
  }

  static const _imageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'};

  Future<void> _view(BuildContext context, WidgetRef ref, MicroPythonController controller, RemoteEntry e) async {
    final bytes = await controller.readBytes(e.name);
    if (bytes == null || !context.mounted) return;

    final ext = e.name.contains('.') ? e.name.split('.').last.toLowerCase() : '';
    if (_imageExtensions.contains(ext)) {
      await showDialog<void>(context: context, builder: (_) => _ImageDialog(name: e.name, bytes: bytes));
      return;
    }

    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(e.name),
          content: Text(context.l10n.mpBinaryFile(bytes.length)),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.commonClose))],
        ),
      );
      return;
    }
    ref.read(editorProvider.notifier).openAndShow(controller.pathOf(e.name), text);
  }

  Future<void> _newFile(BuildContext context, MicroPythonController controller) async {
    final l10n = context.l10n;
    final name = TextEditingController(text: 'test.py');
    final content = TextEditingController(text: l10n.mpNewFileSample);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.mpNewFile),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: InputDecoration(labelText: l10n.mpNameLabel)),
              const SizedBox(height: 8),
              TextField(
                controller: content,
                minLines: 4,
                maxLines: 10,
                decoration: InputDecoration(labelText: l10n.mpContentLabel, border: const OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.mpWriteToBoard)),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) await controller.writeText(name.text.trim(), content.text);
  }

  Future<void> _newFolder(BuildContext context, MicroPythonController controller) async {
    final l10n = context.l10n;
    final name = await showTextInputDialog(
      context,
      title: l10n.mpNewFolder,
      label: l10n.mpNameLabel,
      confirmLabel: l10n.commonCreate,
      cancelLabel: l10n.commonCancel,
    );
    if (name != null) await controller.makeDirectory(name);
  }

  Future<void> _confirmDelete(BuildContext context, MicroPythonController controller, RemoteEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(context.l10n.mpDeleteTitle(e.name)),
        content: Text(context.l10n.mpDeleteWarning),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(context.l10n.commonDelete)),
        ],
      ),
    );
    if (ok == true) await controller.delete(e);
  }
}

class _ImageDialog extends StatelessWidget {
  const _ImageDialog({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.mpImageTitle(name, bytes.length)),
      content: InteractiveViewer(
        child: Image.memory(
          bytes,
          filterQuality: FilterQuality.none,
          errorBuilder: (_, __, ___) => Text(context.l10n.mpImageUnreadable),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.commonClose))],
    );
  }
}
