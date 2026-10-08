import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_editor/nomad_editor.dart';

import '../../application/micropython_controller.dart';
import 'repl_log_view.dart';

/// Journal de la carte, saisie de code et barre d'actions rapides (Tab, symboles, Ctrl+C, Ctrl+D).
class ConsolePanel extends ConsumerStatefulWidget {
  const ConsolePanel({super.key});

  @override
  ConsumerState<ConsolePanel> createState() => _ConsolePanelState();
}

class _ConsolePanelState extends ConsumerState<ConsolePanel> {
  final _code = TextEditingController(text: 'print("Bonjour depuis NomadMCU")');

  static const _snippets = {
    'uname': 'import os\nprint(os.uname())',
    'mémoire': 'import gc\nprint(gc.mem_free())',
    'erreur': 'raise Exception("test")',
    'boucle 3 s': 'import time\nfor i in range(3):\n    print(i)\n    time.sleep(1)',
  };

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _run() => ref.read(microPythonProvider.notifier).run(_code.text);

  /// Insère [text] à la position du curseur de la zone de saisie.
  void _insert(String text) {
    final value = _code.value;
    final selection = value.selection.isValid ? value.selection : TextSelection.collapsed(offset: value.text.length);
    final updated = value.text.replaceRange(selection.start, selection.end, text);
    _code.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: selection.start + text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = ref.watch(microPythonProvider.select((s) => s.isReady));
    final busy = ref.watch(microPythonProvider.select((s) => s.busy));
    final controller = ref.read(microPythonProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Expanded(child: ReplLogView()),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Wrap(
            spacing: 6,
            children: [
              for (final s in _snippets.entries) ActionChip(label: Text(s.key), onPressed: () => _code.text = s.value),
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
                  if (busy)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
                      onPressed: controller.stop,
                      icon: const Icon(Icons.stop),
                      label: const Text('Arrêter'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: ready ? _run : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Exécuter'),
                    ),
                  TextButton(onPressed: controller.clearLog, child: const Text('Effacer')),
                ],
              ),
            ],
          ),
        ),
        QuickKeyBar(
          keys: [
            QuickKey(label: 'Tab', tooltip: 'Insérer une indentation', onPressed: () => _insert('    ')),
            QuickKey(label: ':', tooltip: 'Insérer :', onPressed: () => _insert(':')),
            QuickKey(label: '{', tooltip: 'Insérer {', onPressed: () => _insert('{')),
            QuickKey(label: '}', tooltip: 'Insérer }', onPressed: () => _insert('}')),
            QuickKey(
              label: 'Ctrl+C',
              tooltip: 'Interrompre le programme en cours',
              onPressed: busy ? controller.stop : null,
            ),
            QuickKey(
              label: 'Ctrl+D',
              tooltip: 'Redémarrer l\'interpréteur (soft reset)',
              onPressed: ready && !busy ? controller.softReset : null,
            ),
          ],
        ),
      ],
    );
  }
}
