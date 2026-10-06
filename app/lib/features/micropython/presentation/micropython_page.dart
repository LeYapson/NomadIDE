import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_protocols/nomad_protocols.dart';

import '../application/micropython_controller.dart';

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
      appBar: AppBar(title: const Text('NomadMCU · MicroPython')),
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
                        Expanded(child: _ConsolePanel()),
                      ],
                    );
                  }
                  return const DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        TabBar(tabs: [Tab(text: 'Console'), Tab(text: 'Fichiers')]),
                        Expanded(child: TabBarView(children: [_ConsolePanel(), _FilesPanel()])),
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
            width: 380,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Carte',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<SerialDeviceInfo>(
                  isDense: true,
                  isExpanded: true,
                  value: state.devices.contains(state.selectedDevice) ? state.selectedDevice : null,
                  hint: Text(state.devices.isEmpty ? 'Aucune carte détectée' : 'Choisir une carte'),
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
            tooltip: 'Actualiser la liste',
            onPressed: idle ? controller.refreshDevices : null,
            icon: const Icon(Icons.refresh),
          ),
          switch (state.status) {
            ReplStatus.disconnected => FilledButton.icon(
                onPressed: state.selectedDevice == null ? null : controller.connect,
                icon: const Icon(Icons.usb),
                label: const Text('Connecter (raw REPL)'),
              ),
            ReplStatus.connecting => const FilledButton(onPressed: null, child: Text('Connexion…')),
            ReplStatus.ready => FilledButton.tonalIcon(
                onPressed: state.busy ? null : controller.disconnect,
                icon: const Icon(Icons.usb_off),
                label: const Text('Déconnecter'),
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

class _ConsolePanel extends ConsumerStatefulWidget {
  const _ConsolePanel();

  @override
  ConsumerState<_ConsolePanel> createState() => _ConsolePanelState();
}

class _ConsolePanelState extends ConsumerState<_ConsolePanel> {
  final _scroll = ScrollController();
  final _code = TextEditingController(text: 'print("Bonjour depuis NomadMCU")');

  static const _snippets = {
    'uname': 'import os\nprint(os.uname())',
    'mémoire': 'import gc\nprint(gc.mem_free())',
    'erreur': 'raise Exception("test")',
    'boucle 3 s': 'import time\nfor i in range(3):\n    print(i)\n    time.sleep(1)',
  };

  @override
  void dispose() {
    _scroll.dispose();
    _code.dispose();
    super.dispose();
  }

  void _run() => ref.read(microPythonProvider.notifier).run(_code.text);

  @override
  Widget build(BuildContext context) {
    final log = ref.watch(microPythonProvider.select((s) => s.log));
    final ready = ref.watch(microPythonProvider.select((s) => s.isReady));
    final busy = ref.watch(microPythonProvider.select((s) => s.busy));
    final scheme = Theme.of(context).colorScheme;

    ref.listen(microPythonProvider.select((s) => s.log), (_, __) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    });

    Color colorOf(ReplLogKind kind) => switch (kind) {
          ReplLogKind.info => scheme.outline,
          ReplLogKind.input => scheme.primary,
          ReplLogKind.out => scheme.onSurface,
          ReplLogKind.err => scheme.error,
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SelectionArea(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(8),
              itemCount: log.length,
              itemBuilder: (context, i) {
                final e = log[i];
                final prefix = switch (e.kind) {
                  ReplLogKind.info => '· ',
                  ReplLogKind.input => '>>> ',
                  _ => '',
                };
                return Text(
                  '$prefix${e.text}',
                  style: TextStyle(fontFamily: 'Consolas', fontFamilyFallback: const ['monospace'], color: colorOf(e.kind)),
                );
              },
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Wrap(
            spacing: 6,
            children: [
              for (final s in _snippets.entries)
                ActionChip(label: Text(s.key), onPressed: () => _code.text = s.value),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: CallbackShortcuts(
                  bindings: {const SingleActivator(LogicalKeyboardKey.enter, control: true): _run},
                  child: TextField(
                    controller: _code,
                    minLines: 3,
                    maxLines: 8,
                    style: const TextStyle(fontFamily: 'Consolas', fontFamilyFallback: ['monospace']),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Code MicroPython (Ctrl+Entrée pour exécuter)',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: [
                  FilledButton.icon(
                    onPressed: ready && !busy ? _run : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Exécuter'),
                  ),
                  TextButton(onPressed: ref.read(microPythonProvider.notifier).clearLog, child: const Text('Effacer')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Fichiers
// -----------------------------------------------------------------------------

class _FilesPanel extends ConsumerWidget {
  const _FilesPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                tooltip: 'Dossier parent',
                onPressed: enabled && state.cwd != '/' ? controller.goUp : null,
                icon: const Icon(Icons.arrow_upward),
              ),
              Expanded(child: Text(state.cwd, overflow: TextOverflow.ellipsis)),
              IconButton(
                tooltip: 'Actualiser',
                onPressed: enabled ? controller.refreshFiles : null,
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                tooltip: 'Nouveau fichier',
                onPressed: enabled ? () => _newFile(context, controller) : null,
                icon: const Icon(Icons.note_add_outlined),
              ),
              IconButton(
                tooltip: 'Nouveau dossier',
                onPressed: enabled ? () => _newFolder(context, controller) : null,
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: state.files.isEmpty
              ? Center(child: Text(state.isReady ? 'Dossier vide' : 'Non connecté'))
              : ListView(
                  children: [
                    for (final e in state.files)
                      ListTile(
                        dense: true,
                        enabled: enabled,
                        leading: Icon(e.isDirectory ? Icons.folder_outlined : Icons.insert_drive_file_outlined),
                        title: Text(e.name),
                        subtitle: e.isDirectory || e.size == null ? null : Text('${e.size} o'),
                        onTap: () => e.isDirectory ? controller.openDirectory(e.name) : _view(context, controller, e),
                        trailing: IconButton(
                          tooltip: 'Supprimer',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: enabled ? () => _confirmDelete(context, controller, e) : null,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _view(BuildContext context, MicroPythonController controller, RemoteEntry e) async {
    final text = await controller.readText(e.name);
    if (text == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(e.name),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: SelectableText(
              text.length > 20000 ? '${text.substring(0, 20000)}\n… (tronqué)' : text,
              style: const TextStyle(fontFamily: 'Consolas', fontFamilyFallback: ['monospace']),
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))],
      ),
    );
  }

  Future<void> _newFile(BuildContext context, MicroPythonController controller) async {
    final name = TextEditingController(text: 'test.py');
    final content = TextEditingController(text: 'print("fichier de test")\n');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nouveau fichier'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nom')),
              const SizedBox(height: 8),
              TextField(
                controller: content,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(labelText: 'Contenu', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Écrire sur la carte')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) await controller.writeText(name.text.trim(), content.text);
  }

  Future<void> _newFolder(BuildContext context, MicroPythonController controller) async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nouveau dossier'),
        content: TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Nom')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Créer')),
        ],
      ),
    );
    if (ok == true && name.text.trim().isNotEmpty) await controller.makeDirectory(name.text.trim());
  }

  Future<void> _confirmDelete(BuildContext context, MicroPythonController controller, RemoteEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Supprimer ${e.name} ?'),
        content: const Text('Cette action est définitive.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok == true) await controller.delete(e);
  }
}
