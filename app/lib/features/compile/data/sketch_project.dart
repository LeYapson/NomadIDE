import 'package:nomad_compile_api/nomad_compile_api.dart';

import '../../projects/data/project_store.dart';
import 'project_config.dart';

/// Nom du croquis `.ino` d'un projet : celui du projet, réduit aux caractères qu'Arduino accepte.
String sketchNameFor(String project) {
  final clean = project.trim().replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  return clean.isEmpty ? 'sketch' : (clean.length > 64 ? clean.substring(0, 64) : clean);
}

/// Contenu du croquis de départ. [comment] est la première ligne, dans la langue de l'utilisateur.
String blinkSketch(String comment) => '// $comment\n'
    'void setup() {\n'
    '  pinMode(LED_BUILTIN, OUTPUT);\n'
    '}\n'
    '\n'
    'void loop() {\n'
    '  digitalWrite(LED_BUILTIN, HIGH);\n'
    '  delay(500);\n'
    '  digitalWrite(LED_BUILTIN, LOW);\n'
    '  delay(500);\n'
    '}\n';

/// Remplit un projet neuf avec un croquis Blink et le fichier `nomad.json` (carte par défaut).
/// Renvoie le chemin du croquis.
Future<String> seedSketchProject(
  ProjectStore store,
  String project, {
  required String comment,
  CompileBoard board = CompileBoard.esp32,
}) async {
  final path = '${sketchNameFor(project)}.ino';
  await store.writeText(project, path, blinkSketch(comment));
  await ProjectConfig.writeBoard(store, project, board);
  return path;
}

const List<String> _cppExtensions = ['.ino', '.cpp', '.c', '.h', '.hpp'];

/// Nom proposé pour un nouveau fichier : adapté au langage du dossier (C/C++ ou Python).
String defaultNewFileName(Iterable<String> existingNames) {
  final names = existingNames.map((n) => n.toLowerCase()).toList();
  final cpp = names.any((n) => _cppExtensions.any(n.endsWith));
  final python = names.any((n) => n.endsWith('.py'));
  return cpp && !python ? 'helpers.h' : 'main.py';
}
