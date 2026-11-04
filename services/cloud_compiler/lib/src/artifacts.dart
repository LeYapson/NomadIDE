import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:path/path.dart' as p;

/// Fichier produit, avec son chemin sur le disque du serveur.
class CollectedArtifact {
  const CollectedArtifact(this.info, this.file);

  final BuildArtifact info;
  final File file;
}

/// Rôle d'un fichier de sortie d'après son nom (`<croquis>.ino.merged.bin`, `<croquis>.ino.uf2`…).
/// `null` pour ce qu'on ne propose pas (bootloader et partitions seuls : l'image `merged` les contient).
ArtifactRole? classifyArtifact(String name, CompileFamily family) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.bootloader.bin') || lower.endsWith('.partitions.bin')) return null;
  if (family == CompileFamily.esp) {
    if (lower.endsWith('.merged.bin')) return ArtifactRole.merged;
    if (lower.endsWith('.bin')) return ArtifactRole.app;
  } else if (lower.endsWith('.uf2')) {
    return ArtifactRole.uf2;
  }
  if (lower.endsWith('.elf') || lower.endsWith('.map')) return ArtifactRole.debug;
  return null;
}

/// Liste les fichiers utiles de [outDir], triés (flashables d'abord).
Future<List<CollectedArtifact>> collectArtifacts(Directory outDir, CompileBoard board) async {
  final found = <CollectedArtifact>[];
  if (!await outDir.exists()) return found;
  await for (final entity in outDir.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    final role = classifyArtifact(name, board.family);
    if (role == null) continue;
    final digest = await sha256.bind(entity.openRead()).first;
    found.add(CollectedArtifact(
      BuildArtifact(name: name, role: role, size: await entity.length(), sha256: digest.toString()),
      entity,
    ));
  }
  found.sort((a, b) {
    final byRole = a.info.role.index.compareTo(b.info.role.index);
    return byRole != 0 ? byRole : a.info.name.compareTo(b.info.name);
  });
  return found;
}
