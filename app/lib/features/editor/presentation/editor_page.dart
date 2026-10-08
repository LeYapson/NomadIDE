import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_editor/nomad_editor.dart';

import '../../micropython/application/micropython_controller.dart';
import '../../micropython/presentation/widgets/repl_log_view.dart';
import '../application/editor_controller.dart';

/// Éditeur de code : onglets de fichiers, coloration, exécution sur la carte,
/// barre de symboles sur mobile et sortie repliable.
class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({super.key});

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  bool _showOutput = false;

  /// Écran tactile : la barre de symboles remplace les touches absentes du clavier.
  static bool get _isMobile => defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _save(EditorDocument document) async {
    var path = document.boardPath;
    if (path == null) {
      final suggestion = ref.read(microPythonProvider.notifier).pathOf(document.name);
      path = await _askPath(suggestion);
      if (path == null) return;
    }
    if (!mounted) return;
    final saved = await ref.read(editorProvider.notifier).saveToBoard(document, path: path);
    if (saved && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Enregistré sur la carte : $path (CRC32 vérifié)')));
    }
  }

  Future<String?> _askPath(String suggestion) {
    final field = TextEditingController(text: suggestion);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enregistrer sur la carte'),
        content: TextField(
          controller: field,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Chemin sur la carte', helperText: 'Ex. /main.py (lancé au démarrage)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final path = field.text.trim();
              Navigator.pop(context, path.isEmpty ? null : (path.startsWith('/') ? path : '/$path'));
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  Future<void> _run(EditorDocument document) async {
    setState(() => _showOutput = true);
    await ref.read(editorProvider.notifier).run(document);
  }

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(editorProvider);
    final micro = ref.watch(microPythonProvider);
    final controller = ref.read(editorProvider.notifier);
    final document = editor.active;

    return Scaffold(
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
                tooltip: micro.isReady ? 'Enregistrer sur la carte' : 'Connectez une carte (onglet MicroPython)',
                onPressed: micro.isReady && !micro.busy ? () => _save(document) : null,
                icon: Icon(document.dirty ? Icons.save : Icons.save_outlined),
              ),
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
                tooltip: micro.isReady ? 'Exécuter la sélection ou le fichier sur la carte (sans enregistrer)' : 'Connectez une carte (onglet MicroPython)',
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
      body: SafeArea(
        child: document == null
            ? _EmptyState(onNew: controller.newDocument)
            : Column(
                children: [
                  _DocumentTabs(editor: editor),
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
                        if (constraints.maxWidth >= 840) {
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
              'Créez un fichier, ou touchez un fichier de la carte dans l\'onglet MicroPython pour l\'ouvrir ici.',
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
  const _DocumentTabs({required this.editor});

  final EditorState editor;

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
                      onPressed: () => controller.close(document),
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
