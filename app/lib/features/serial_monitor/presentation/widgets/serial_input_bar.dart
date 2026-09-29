import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../application/serial_monitor_controller.dart';
import '../../application/serial_monitor_state.dart';

/// Champ de saisie, avec historique des commandes (↑ / ↓ sur desktop).
class SerialInputBar extends ConsumerStatefulWidget {
  const SerialInputBar({super.key});

  @override
  ConsumerState<SerialInputBar> createState() => _SerialInputBarState();
}

class _SerialInputBarState extends ConsumerState<SerialInputBar> {
  static const _maxHistory = 100;

  final TextEditingController _text = TextEditingController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  final List<String> _history = [];
  int _historyIndex = 0; // == _history.length : saisie en cours

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _text.text;
    // Une ligne vide est envoyée aussi : « Entrée » au REPL affiche une nouvelle invite.
    ref.read(serialMonitorProvider.notifier).send(text);
    if (text.isNotEmpty && (_history.isEmpty || _history.last != text)) {
      _history.add(text);
      if (_history.length > _maxHistory) _history.removeAt(0);
    }
    _historyIndex = _history.length;
    _text.clear();
    _focus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (_history.isEmpty) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_historyIndex > 0) _historyIndex--;
      _show(_history[_historyIndex]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_historyIndex < _history.length - 1) {
        _historyIndex++;
        _show(_history[_historyIndex]);
      } else {
        _historyIndex = _history.length;
        _show('');
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _show(String text) {
    _text.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(serialMonitorProvider.select((s) => s.isConnected));
    final lineEnding = ref.watch(serialMonitorProvider.select((s) => s.lineEnding));
    final controller = ref.read(serialMonitorProvider.notifier);

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _text,
              focusNode: _focus,
              enabled: connected,
              style: monoTextStyle,
              // Clavier mobile : pas de correction ni de guillemets « intelligents » dans du code.
              autocorrect: false,
              enableSuggestions: false,
              smartQuotesType: SmartQuotesType.disabled,
              smartDashesType: SmartDashesType.disabled,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                isDense: true,
                border: const OutlineInputBorder(),
                hintText: connected ? 'Commande… (Entrée pour envoyer, ↑/↓ historique)' : 'Connectez une carte',
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: "Fin de ligne ajoutée à l'envoi",
            child: DropdownButton<LineEnding>(
              value: lineEnding,
              underline: const SizedBox.shrink(),
              items: [
                for (final ending in LineEnding.values) DropdownMenuItem(value: ending, child: Text(ending.label)),
              ],
              onChanged: (ending) {
                if (ending != null) controller.setLineEnding(ending);
              },
            ),
          ),
          const SizedBox(width: 4),
          IconButton.filled(
            tooltip: 'Envoyer',
            onPressed: connected ? _submit : null,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}
