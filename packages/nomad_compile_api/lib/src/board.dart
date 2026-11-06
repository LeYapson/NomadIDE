/// Famille de carte, qui décide de l'artefact à flasher.
enum CompileFamily { esp, rp2040 }

/// Cartes que le service sait compiler. [id] est la valeur échangée sur le réseau.
enum CompileBoard {
  esp32('esp32', 'ESP32', 'esp32:esp32:esp32', CompileFamily.esp),
  esp32s2('esp32s2', 'ESP32-S2', 'esp32:esp32:esp32s2', CompileFamily.esp),
  esp32s3('esp32s3', 'ESP32-S3', 'esp32:esp32:esp32s3', CompileFamily.esp),
  rp2040('rp2040', 'RP2040 (Pico, Badger 2040)', 'rp2040:rp2040:rpipico', CompileFamily.rp2040);

  const CompileBoard(this.id, this.label, this.fqbn, this.family);

  final String id;
  final String label;

  /// Nom complet de carte d'`arduino-cli` : `fabricant:architecture:carte`.
  final String fqbn;
  final CompileFamily family;

  /// Architecture déclarée par les bibliothèques de l'index (`architectures=` de `library.properties`).
  String get architecture => family == CompileFamily.rp2040 ? 'rp2040' : 'esp32';

  static CompileBoard? fromId(String? id) {
    for (final board in values) {
      if (board.id == id) return board;
    }
    return null;
  }
}
