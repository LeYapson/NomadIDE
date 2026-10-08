/// NomadMCU — éditeur de code (Python / C / C++) pour écran tactile et desktop.
library;

export 'src/code_language.dart';
export 'src/nomad_code_editor.dart';
export 'src/nomad_editor_controller.dart';
export 'src/quick_key_bar.dart';

// Types de re_editor nécessaires pour piloter le curseur sans dépendre du package.
export 'package:re_editor/re_editor.dart' show CodeEditor, CodeLineSelection;
