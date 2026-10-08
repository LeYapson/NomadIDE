import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:re_editor/re_editor.dart';

import 'code_language.dart';

/// État d'édition d'un document : texte, curseur, annuler/rétablir et règles
/// d'indentation propres au langage.
///
/// re_editor indente déjà entre `{` et `}` ; ce contrôleur ajoute le bloc Python
/// (un niveau après une ligne qui finit par `:`).
class NomadEditorController extends ChangeNotifier {
  NomadEditorController({String text = '', this.language = CodeLanguage.plain})
      : code = CodeLineEditingController.fromText(
          text,
          CodeLineOptions(indentSize: language.indentSize),
        ) {
    _lineCount = code.codeLines.length;
    _caretLine = code.selection.startIndex;
    code.addListener(_onCodeChanged);
  }

  final CodeLineEditingController code;
  final CodeLanguage language;

  int _lineCount = 0;
  int _caretLine = 0;
  bool _adjusting = false;
  bool _disposed = false;
  bool _notifyScheduled = false;

  String get text => code.text;

  set text(String value) => code.text = value;

  bool get canUndo => code.canUndo;
  bool get canRedo => code.canRedo;

  void undo() => code.undo();

  void redo() => code.redo();

  /// Insère [text] à la position du curseur (remplace la sélection).
  void insert(String text) => code.replaceSelection(text);

  /// Insère une indentation (ou indente la sélection).
  void indent() => code.applyIndent();

  void _onCodeChanged() {
    if (_adjusting) return;
    final lines = code.codeLines;
    final selection = code.selection;
    final newlineTyped = language == CodeLanguage.python &&
        lines.length == _lineCount + 1 &&
        selection.isCollapsed &&
        selection.startIndex == _caretLine + 1;
    if (newlineTyped) _indentAfterColon(selection.startIndex);
    _lineCount = code.codeLines.length;
    _caretLine = code.selection.startIndex;
    _notifySafely();
  }

  /// re_editor modifie le contrôleur pendant sa construction ou sa mise en page :
  /// prévenir alors les widgets à l'écoute (onglets, barre d'actions) lèverait
  /// « setState() called during build ». On diffère donc à la fin de la frame.
  void _notifySafely() {
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      notifyListeners();
      return;
    }
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    binding.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  void _indentAfterColon(int lineIndex) {
    final lines = code.codeLines;
    final previous = lines[lineIndex - 1].text.trimRight();
    final current = lines[lineIndex].text;
    // Seule la ligne vide créée par Entrée est concernée (pas un collage).
    if (!previous.endsWith(':') || current.trim().isNotEmpty) return;
    if (code.selection.startOffset != current.length) return;
    _adjusting = true;
    try {
      code.replaceSelection(' ' * language.indentSize);
    } finally {
      _adjusting = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    code.removeListener(_onCodeChanged);
    code.dispose();
    super.dispose();
  }
}
