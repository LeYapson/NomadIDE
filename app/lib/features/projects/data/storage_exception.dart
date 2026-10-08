/// Cause d'un échec de stockage local, pour que l'interface choisisse son message.
enum StorageError {
  /// Nom vide, trop long, caractères interdits ou nom réservé par le système.
  invalidName,

  /// Un projet, un fichier ou un dossier de ce nom existe déjà.
  alreadyExists,

  /// Projet, fichier ou dossier introuvable.
  notFound,

  /// Chemin qui sortirait du projet (`..`).
  outsideProject,

  /// Échec du système de fichiers (disque plein, permission…).
  io,
}

class StorageException implements Exception {
  const StorageException(this.error, {this.name, this.cause});

  final StorageError error;

  /// Nom concerné (projet, fichier…), s'il y en a un.
  final String? name;

  final Object? cause;

  @override
  String toString() => 'StorageException(${error.name}${name == null ? '' : ', $name'}${cause == null ? '' : ', $cause'})';
}
