/// Où en est une compilation.
enum BuildState {
  queued,
  running,
  succeeded,
  failed,
  timedOut,
  cancelled;

  bool get isFinished => this == succeeded || this == failed || this == timedOut || this == cancelled;

  static BuildState parse(String? name) => values.firstWhere((s) => s.name == name, orElse: () => failed);
}

enum DiagnosticSeverity { error, warning, note }

/// Une erreur ou un avertissement du compilateur, localisé dans un fichier du projet.
class Diagnostic {
  const Diagnostic({
    required this.file,
    required this.line,
    required this.severity,
    required this.message,
    this.column,
    this.notes = const [],
  });

  final String file;
  final int line;
  final int? column;
  final DiagnosticSeverity severity;
  final String message;

  /// Lignes « note: » du compilateur qui expliquent le diagnostic.
  final List<String> notes;

  Diagnostic withNote(String note) =>
      Diagnostic(file: file, line: line, column: column, severity: severity, message: message, notes: [...notes, note]);

  Map<String, Object?> toJson() => {
        'file': file,
        'line': line,
        if (column != null) 'column': column,
        'severity': severity.name,
        'message': message,
        if (notes.isNotEmpty) 'notes': notes,
      };

  factory Diagnostic.fromJson(Map<String, Object?> json) => Diagnostic(
        file: json['file'] as String,
        line: json['line'] as int,
        column: json['column'] as int?,
        severity: DiagnosticSeverity.values.firstWhere(
          (s) => s.name == json['severity'],
          orElse: () => DiagnosticSeverity.error,
        ),
        message: json['message'] as String,
        notes: [for (final n in (json['notes'] as List?) ?? const []) n as String],
      );
}

/// Rôle d'un fichier produit : décide comment l'app le propose au flash.
enum ArtifactRole {
  /// Image complète à écrire à l'adresse 0 (ESP : bootloader, partitions et application réunis).
  merged,

  /// Application seule (ESP), à écrire à son adresse de partition.
  app,

  /// Fichier UF2 à copier sur le disque BOOTSEL (RP2040).
  uf2,

  /// Fichier de débogage (ELF, carte mémoire) : non flashable.
  debug;

  static ArtifactRole parse(String? name) => values.firstWhere((r) => r.name == name, orElse: () => debug);
}

class BuildArtifact {
  const BuildArtifact({required this.name, required this.role, required this.size, required this.sha256});

  final String name;
  final ArtifactRole role;
  final int size;
  final String sha256;

  Map<String, Object?> toJson() => {'name': name, 'role': role.name, 'size': size, 'sha256': sha256};

  factory BuildArtifact.fromJson(Map<String, Object?> json) => BuildArtifact(
        name: json['name'] as String,
        role: ArtifactRole.parse(json['role'] as String?),
        size: json['size'] as int,
        sha256: json['sha256'] as String,
      );
}

/// Réponse de `GET /v1/builds/{id}`.
class BuildStatus {
  const BuildStatus({
    required this.id,
    required this.state,
    required this.board,
    this.log = '',
    this.diagnostics = const [],
    this.artifacts = const [],
    this.message,
    this.queuePosition,
    this.durationMs,
  });

  final String id;
  final BuildState state;
  final String board;

  /// Sortie du compilateur (tronquée côté serveur).
  final String log;
  final List<Diagnostic> diagnostics;
  final List<BuildArtifact> artifacts;

  /// Explication d'un échec qui ne vient pas du code (projet invalide, délai dépassé…).
  final String? message;

  /// Rang dans la file quand [state] vaut `queued` (0 : prochain).
  final int? queuePosition;
  final int? durationMs;

  Map<String, Object?> toJson() => {
        'id': id,
        'state': state.name,
        'board': board,
        'log': log,
        'diagnostics': [for (final d in diagnostics) d.toJson()],
        'artifacts': [for (final a in artifacts) a.toJson()],
        if (message != null) 'message': message,
        if (queuePosition != null) 'queuePosition': queuePosition,
        if (durationMs != null) 'durationMs': durationMs,
      };

  factory BuildStatus.fromJson(Map<String, Object?> json) => BuildStatus(
        id: json['id'] as String,
        state: BuildState.parse(json['state'] as String?),
        board: json['board'] as String,
        log: (json['log'] as String?) ?? '',
        diagnostics: [
          for (final d in (json['diagnostics'] as List?) ?? const []) Diagnostic.fromJson((d as Map).cast()),
        ],
        artifacts: [
          for (final a in (json['artifacts'] as List?) ?? const []) BuildArtifact.fromJson((a as Map).cast()),
        ],
        message: json['message'] as String?,
        queuePosition: json['queuePosition'] as int?,
        durationMs: json['durationMs'] as int?,
      );
}
