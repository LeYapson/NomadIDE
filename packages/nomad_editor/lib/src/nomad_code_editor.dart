import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

import 'code_language.dart';
import 'nomad_editor_controller.dart';

/// Éditeur de code avec numéros de ligne et coloration syntaxique, qui suit le
/// thème clair/sombre de l'application.
class NomadCodeEditor extends StatelessWidget {
  const NomadCodeEditor({
    super.key,
    required this.controller,
    this.readOnly = false,
    this.fontSize = 14,
    this.wordWrap = false,
    this.focusNode,
    this.onChanged,
  });

  final NomadEditorController controller;
  final bool readOnly;
  final double fontSize;
  final bool wordWrap;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;

  static CodeHighlightTheme highlightTheme(CodeLanguage language, Brightness brightness) {
    final theme = brightness == Brightness.dark ? atomOneDarkTheme : atomOneLightTheme;
    final languages = switch (language) {
      CodeLanguage.python => {'python': CodeHighlightThemeMode(mode: langPython)},
      CodeLanguage.c => {'c': CodeHighlightThemeMode(mode: langC)},
      CodeLanguage.cpp => {'cpp': CodeHighlightThemeMode(mode: langCpp)},
      CodeLanguage.plain => <String, CodeHighlightThemeMode>{},
    };
    return CodeHighlightTheme(languages: languages, theme: theme);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final highlight = highlightTheme(controller.language, brightness);
    // Le fond du thème de coloration prime : texte et numéros restent lisibles.
    final background = highlight.theme['root']?.backgroundColor ?? scheme.surface;
    final foreground = highlight.theme['root']?.color ?? scheme.onSurface;

    return CodeEditor(
      controller: controller.code,
      focusNode: focusNode,
      readOnly: readOnly,
      wordWrap: wordWrap,
      onChanged: onChanged == null ? null : (_) => onChanged!(controller.text),
      style: CodeEditorStyle(
        fontSize: fontSize,
        fontFamily: 'Consolas',
        fontFamilyFallback: const ['Roboto Mono', 'monospace'],
        backgroundColor: background,
        textColor: foreground,
        codeTheme: highlight,
      ),
      indicatorBuilder: (context, editingController, chunkController, notifier) => Row(
        children: [
          DefaultCodeLineNumber(
            controller: editingController,
            notifier: notifier,
            textStyle: TextStyle(color: foreground.withValues(alpha: 0.45), fontSize: fontSize),
            focusedTextStyle: TextStyle(color: foreground, fontSize: fontSize),
          ),
          DefaultCodeChunkIndicator(width: 20, controller: chunkController, notifier: notifier),
        ],
      ),
    );
  }
}
