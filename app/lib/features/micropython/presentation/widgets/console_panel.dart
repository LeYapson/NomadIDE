import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_editor/nomad_editor.dart';

import '../../../../l10n/l10n.dart';
import '../../application/micropython_controller.dart';
import 'repl_log_view.dart';

/// Journal de la carte, saisie de code et barre d'actions rapides (Tab, symboles, Ctrl+C, Ctrl+D).
class ConsolePanel extends ConsumerStatefulWidget {
  const ConsolePanel({super.key});

  @override
  ConsumerState<ConsolePanel> createState() => _ConsolePanelState();
}

class _ConsolePanelState extends ConsumerState<ConsolePanel> {
  final _code = TextEditingController();
  bool _seeded = false;

  /// Exemples cliquables : étiquette → code.
  Map<String, String> _snippets(AppLocalizations l10n) => {
        'uname': 'import os\nprint(os.uname())',
        l10n.snippetMemory: 'import gc\nprint(gc.mem_free())',
        l10n.snippetError: 'raise Exception("test")',
        l10n.snippetLoop: 'import time\nfor i in range(3):\n    print(i)\n    time.sleep(1)',
        l10n.snippetInfinite: 'import time\nn = 0\nwhile True:\n    print(n)\n    n += 1\n    time.sleep(0.5)',
      };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Le texte d'exemple dépend de la langue : il n'est posé qu'une fois.
    if (!_seeded) {
      _seeded = true;
      _code.text = context.l10n.mpDefaultCode;
    }
  }

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
    final l10n = context.l10n;
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
          // Une seule ligne qui défile : sur un petit écran, des pastilles sur plusieurs lignes
          // écraseraient le journal.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final s in _snippets(l10n).entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(label: Text(s.key), onPressed: () => _code.text = s.value),
                  ),
              ],
            ),
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
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: l10n.mpConsoleHint,
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
                      label: Text(l10n.mpStop),
                    )
                  else
                    FilledButton.icon(
                      onPressed: ready ? _run : null,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(l10n.mpRun),
                    ),
                  TextButton(onPressed: controller.clearLog, child: Text(l10n.monClear)),
                ],
              ),
            ],
          ),
        ),
        QuickKeyBar(
          keys: [
            QuickKey(label: 'Tab', tooltip: l10n.qkTabTooltip, onPressed: () => _insert('    ')),
            QuickKey(label: ':', tooltip: l10n.qkInsert(':'), onPressed: () => _insert(':')),
            QuickKey(label: '{', tooltip: l10n.qkInsert('{'), onPressed: () => _insert('{')),
            QuickKey(label: '}', tooltip: l10n.qkInsert('}'), onPressed: () => _insert('}')),
            QuickKey(
              label: 'Ctrl+C',
              tooltip: l10n.qkCtrlCTooltip,
              onPressed: busy ? controller.stop : null,
            ),
            QuickKey(
              label: 'Ctrl+D',
              tooltip: l10n.qkCtrlDTooltip,
              onPressed: ready && !busy ? controller.softReset : null,
            ),
          ],
        ),
      ],
    );
  }
}
