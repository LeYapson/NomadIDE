/// Réglages du service, lus dans l'environnement (voir README).
class ServerConfig {
  const ServerConfig({
    required this.token,
    this.host = '127.0.0.1',
    this.port = 8787,
    this.dockerImage = 'nomad-compiler:latest',
    this.workDir = '/var/lib/nomad-compiler',
    this.maxConcurrentBuilds = 2,
    this.maxQueuedBuilds = 8,
    this.buildTimeout = const Duration(minutes: 5),
    this.maxUploadBytes = 8 * 1024 * 1024,
    this.maxProjectBytes = 32 * 1024 * 1024,
    this.maxProjectFiles = 500,
    this.jobRetention = const Duration(minutes: 30),
    this.containerMemory = '3g',
    this.containerCpus = '2',
    this.containerPids = 512,
    this.runAs = '1000:1000',
    this.dockerBinary = 'docker',
    this.libraryCacheDir,
    this.libraryIndexUrl = 'https://downloads.arduino.cc/libraries/library_index.json.gz',
  });

  /// Jeton attendu dans `Authorization: Bearer`. Un jeton trop court est refusé au démarrage.
  final String token;
  final String host;
  final int port;
  final String dockerImage;

  /// Dossier des builds en cours. Chaque build y vit dans `<id>/` puis est supprimé.
  final String workDir;
  final int maxConcurrentBuilds;
  final int maxQueuedBuilds;
  final Duration buildTimeout;
  final int maxUploadBytes;
  final int maxProjectBytes;
  final int maxProjectFiles;

  /// Durée pendant laquelle un build terminé (et ses binaires) reste téléchargeable.
  /// Le code source, lui, est supprimé dès la fin de la compilation.
  final Duration jobRetention;
  final String containerMemory;
  final String containerCpus;
  final int containerPids;

  /// `uid:gid` du processus dans le conteneur ; doit pouvoir écrire dans [workDir].
  final String runAs;
  final String dockerBinary;

  /// Où sont installées les bibliothèques Arduino (partagées entre les builds) ; par défaut `<workDir>/libraries`.
  final String? libraryCacheDir;

  /// Index officiel des bibliothèques Arduino.
  final String libraryIndexUrl;

  static const int minTokenLength = 24;

  factory ServerConfig.fromEnvironment(Map<String, String> env) {
    final token = env['NOMAD_TOKEN'] ?? '';
    if (token.length < minTokenLength) {
      throw ConfigException(
        'NOMAD_TOKEN doit faire au moins $minTokenLength caractères (par exemple : openssl rand -hex 32).',
      );
    }
    int number(String key, int fallback) {
      final raw = env[key];
      if (raw == null || raw.isEmpty) return fallback;
      final value = int.tryParse(raw);
      if (value == null || value <= 0) throw ConfigException('$key doit être un entier positif (reçu « $raw »).');
      return value;
    }

    return ServerConfig(
      token: token,
      host: env['NOMAD_HOST'] ?? '127.0.0.1',
      port: number('NOMAD_PORT', 8787),
      dockerImage: env['NOMAD_DOCKER_IMAGE'] ?? 'nomad-compiler:latest',
      workDir: env['NOMAD_WORK_DIR'] ?? '/var/lib/nomad-compiler',
      maxConcurrentBuilds: number('NOMAD_MAX_JOBS', 2),
      maxQueuedBuilds: number('NOMAD_MAX_QUEUE', 8),
      buildTimeout: Duration(seconds: number('NOMAD_BUILD_TIMEOUT_S', 300)),
      maxUploadBytes: number('NOMAD_MAX_UPLOAD_MB', 8) * 1024 * 1024,
      jobRetention: Duration(minutes: number('NOMAD_JOB_RETENTION_MIN', 30)),
      containerMemory: env['NOMAD_CONTAINER_MEMORY'] ?? '3g',
      containerCpus: env['NOMAD_CONTAINER_CPUS'] ?? '2',
      runAs: env['NOMAD_RUN_AS'] ?? '1000:1000',
      libraryCacheDir: env['NOMAD_LIB_CACHE'],
      libraryIndexUrl: env['NOMAD_LIB_INDEX_URL'] ?? 'https://downloads.arduino.cc/libraries/library_index.json.gz',
    );
  }
}

class ConfigException implements Exception {
  ConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}
