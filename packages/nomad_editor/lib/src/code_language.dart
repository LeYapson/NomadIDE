/// Langages pris en charge par l'éditeur (coloration et indentation).
enum CodeLanguage {
  python('Python', 4),
  c('C', 2),
  cpp('C++', 2),
  plain('Texte', 2);

  const CodeLanguage(this.label, this.indentSize);

  final String label;
  final int indentSize;

  /// Déduit le langage de l'extension ; [plain] si elle est inconnue.
  static CodeLanguage fromFileName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return plain;
    return switch (name.substring(dot + 1).toLowerCase()) {
      'py' || 'pyi' => python,
      'c' || 'h' => c,
      'cpp' || 'cc' || 'cxx' || 'hpp' || 'hh' || 'hxx' || 'ino' => cpp,
      _ => plain,
    };
  }
}
