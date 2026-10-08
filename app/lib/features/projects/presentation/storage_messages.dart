import '../data/storage_exception.dart';

/// Message lisible pour une erreur de stockage local.
String storageErrorMessage(StorageException e) {
  final name = e.name == null ? '' : '« ${e.name} »';
  return switch (e.error) {
    StorageError.invalidName =>
      'Nom invalide $name. Évitez les caractères / \\ : * ? " < > | et les noms réservés (CON, NUL…).',
    StorageError.alreadyExists => '$name existe déjà.',
    StorageError.notFound => '$name est introuvable.',
    StorageError.outsideProject => 'Chemin refusé $name : il sortirait du projet.',
    StorageError.io => 'Erreur de stockage ${e.name == null ? '' : 'sur $name '}: ${e.cause ?? 'inconnue'}.',
  };
}
