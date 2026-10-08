import 'dart:math';

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';

import 'code_language.dart';
import 'nomad_editor_controller.dart';

const _pythonKeywords = [
  'False', 'None', 'True', 'and', 'as', 'assert', 'async', 'await', 'break', 'class', 'continue', 'def', 'del',
  'elif', 'else', 'except', 'finally', 'for', 'from', 'global', 'if', 'import', 'in', 'is', 'lambda', 'nonlocal',
  'not', 'or', 'pass', 'raise', 'return', 'try', 'while', 'with', 'yield',
  // Fonctions et types natifs courants
  'abs', 'bytearray', 'bytes', 'dict', 'enumerate', 'float', 'input', 'int', 'isinstance', 'len', 'list', 'map',
  'max', 'min', 'open', 'print', 'range', 'round', 'set', 'sorted', 'str', 'sum', 'tuple', 'zip',
];

/// Modules et classes MicroPython les plus utilisés (machine, time, réseau, NeoPixel…).
const _micropythonNames = [
  'machine', 'Pin', 'PWM', 'ADC', 'I2C', 'SoftI2C', 'SPI', 'SoftSPI', 'UART', 'Timer', 'RTC', 'WDT', 'freq',
  'reset', 'soft_reset', 'deepsleep', 'lightsleep', 'time', 'utime', 'sleep', 'sleep_ms', 'sleep_us', 'ticks_ms',
  'ticks_us', 'ticks_diff', 'ticks_add', 'os', 'uos', 'listdir', 'ilistdir', 'mkdir', 'remove', 'rename', 'stat',
  'gc', 'collect', 'mem_free', 'mem_alloc', 'sys', 'network', 'WLAN', 'STA_IF', 'AP_IF', 'isconnected', 'ifconfig',
  'urequests', 'socket', 'json', 'neopixel', 'NeoPixel', 'framebuf', 'FrameBuffer', 'micropython', 'const',
  'badger2040', 'Badger2040', 'bluetooth', 'BLE', 'uasyncio', 'asyncio', 'create_task', 'gather', 'IN', 'OUT',
  'PULL_UP', 'PULL_DOWN', 'IRQ_RISING', 'IRQ_FALLING', 'duty_u16', 'read_u16', 'value', 'toggle', 'on', 'off',
];

const _cKeywords = [
  'auto', 'break', 'case', 'char', 'const', 'continue', 'default', 'do', 'double', 'else', 'enum', 'extern',
  'float', 'for', 'goto', 'if', 'inline', 'int', 'long', 'register', 'return', 'short', 'signed', 'sizeof',
  'static', 'struct', 'switch', 'typedef', 'union', 'unsigned', 'void', 'volatile', 'while', 'bool', 'true',
  'false', 'NULL', 'uint8_t', 'uint16_t', 'uint32_t', 'int8_t', 'int16_t', 'int32_t', 'size_t', 'include',
  'define', 'ifdef', 'ifndef', 'endif', 'printf', 'malloc', 'free', 'memcpy', 'memset', 'strlen',
];

const _cppKeywords = [
  ..._cKeywords,
  'class', 'namespace', 'template', 'typename', 'public', 'private', 'protected', 'virtual', 'override', 'new',
  'delete', 'nullptr', 'using', 'try', 'catch', 'throw', 'constexpr', 'auto', 'std', 'string', 'vector', 'cout',
  // API Arduino fréquente en .ino / .cpp
  'setup', 'loop', 'pinMode', 'digitalWrite', 'digitalRead', 'analogRead', 'analogWrite', 'delay', 'millis',
  'micros', 'Serial', 'begin', 'println', 'HIGH', 'LOW', 'INPUT', 'OUTPUT', 'INPUT_PULLUP',
];

/// Construit les suggestions : mots-clés du langage, noms MicroPython courants et
/// identifiants déjà présents dans le fichier.
class NomadPromptsBuilder implements CodeAutocompletePromptsBuilder {
  NomadPromptsBuilder(this.controller)
      : _keywords = switch (controller.language) {
          CodeLanguage.python => {..._pythonKeywords, ..._micropythonNames},
          CodeLanguage.c => _cKeywords.toSet(),
          CodeLanguage.cpp => _cppKeywords.toSet(),
          CodeLanguage.plain => <String>{},
        };

  final NomadEditorController controller;
  final Set<String> _keywords;

  /// Nombre minimal de caractères tapés avant de proposer quoi que ce soit.
  static const minInput = 2;
  static const maxPrompts = 12;

  static final _identifierEnd = RegExp(r'[A-Za-z_][A-Za-z0-9_]*$');

  @override
  CodeAutocompleteEditingValue? build(BuildContext context, CodeLine codeLine, CodeLineSelection selection) {
    final text = codeLine.text;
    final caret = min(selection.extentOffset, text.length);
    final before = text.substring(0, caret);
    final input = _identifierEnd.firstMatch(before)?.group(0);
    if (input == null || input.length < minInput) return null;
    if (_insideCommentOrString(before)) return null;

    final candidates = {..._keywords, ...controller.documentSymbols};
    final matches = candidates.where((word) => word != input && word.startsWith(input)).toList()
      ..sort((a, b) => a.length != b.length ? a.length.compareTo(b.length) : a.compareTo(b));
    if (matches.isEmpty) return null;
    return CodeAutocompleteEditingValue(
      input: input,
      prompts: [for (final word in matches.take(maxPrompts)) CodeKeywordPrompt(word: word)],
      index: 0,
    );
  }

  bool _insideCommentOrString(String before) {
    final comment = controller.language == CodeLanguage.python ? '#' : '//';
    if (before.contains(comment)) return true;
    // Nombre impair de guillemets avant le curseur : on est dans une chaîne.
    var quotes = 0;
    for (final char in before.split('')) {
      if (char == '"' || char == "'") quotes++;
    }
    return quotes.isOdd;
  }
}

/// Liste déroulante des suggestions, au toucher comme à la souris.
class PromptListView extends StatelessWidget implements PreferredSizeWidget {
  const PromptListView({super.key, required this.notifier, required this.onSelected});

  static const itemHeight = 40.0;
  static const visibleItems = 5;

  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;

  @override
  Size get preferredSize => Size(220, min(notifier.value.prompts.length, visibleItems) * itemHeight + 2);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<CodeAutocompleteEditingValue>(
      valueListenable: notifier,
      builder: (context, value, _) => Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        color: scheme.surfaceContainerHighest,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: preferredSize.height, maxWidth: preferredSize.width),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemExtent: itemHeight,
            itemCount: value.prompts.length,
            itemBuilder: (context, i) {
              final selected = i == value.index;
              return InkWell(
                onTap: () => onSelected(value.copyWith(index: i).autocomplete),
                child: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  color: selected ? scheme.primaryContainer : null,
                  child: Text(
                    value.prompts[i].word,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Consolas',
                      fontFamilyFallback: const ['Roboto Mono', 'monospace'],
                      color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
