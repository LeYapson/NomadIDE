import 'build_models.dart';

final RegExp _diagnosticLine = RegExp(r'^(.+?):(\d+):(?:(\d+):)?\s*(fatal error|error|warning|note):\s*(.*)$');

/// Extrait les erreurs et avertissements d'une sortie de compilation gcc.
///
/// [sourceRoots] liste les préfixes à retirer pour obtenir un chemin relatif au projet
/// (par exemple `/work/sketch`). Les lignes qui ne sont pas des diagnostics sont ignorées ; une note
/// n'est gardée que jointe à l'erreur ou à l'avertissement qui la précède.
List<Diagnostic> parseCompilerOutput(String output, {List<String> sourceRoots = const []}) {
  final found = <Diagnostic>[];
  for (final raw in output.split('\n')) {
    final line = raw.trimRight();
    final match = _diagnosticLine.firstMatch(line);
    if (match == null) continue;
    final severity = switch (match.group(4)) {
      'warning' => DiagnosticSeverity.warning,
      'note' => DiagnosticSeverity.note,
      _ => DiagnosticSeverity.error,
    };
    final diagnostic = Diagnostic(
      file: _relative(match.group(1)!, sourceRoots),
      line: int.parse(match.group(2)!),
      column: int.tryParse(match.group(3) ?? ''),
      severity: severity,
      message: match.group(5)!.trim(),
    );
    if (severity == DiagnosticSeverity.note) {
      if (found.isNotEmpty) {
        final previous = found.removeLast();
        found.add(previous.withNote('${diagnostic.file}:${diagnostic.line}: ${diagnostic.message}'));
      }
    } else {
      found.add(diagnostic);
    }
  }
  return found;
}

String _relative(String path, List<String> roots) {
  final normalized = path.replaceAll('\\', '/');
  for (final root in roots) {
    final prefix = root.endsWith('/') ? root : '$root/';
    if (normalized.startsWith(prefix)) return normalized.substring(prefix.length);
  }
  return normalized;
}
