import 'dart:convert';
import 'dart:typed_data';

import 'esp_image.dart';
import 'esp_loader.dart';

/// Rôle d'un fichier dans un flash ESP en plusieurs parties (projet Arduino ou ESP-IDF compilé).
enum EspPartRole {
  /// Image complète (bootloader, table de partitions et application), comme le firmware MicroPython.
  fullImage,

  /// Second bootloader (`bootloader.bin`).
  bootloader,

  /// Table de partitions (`partitions.bin`, `partition-table.bin`).
  partitionTable,

  /// Données de démarrage OTA (`boot_app0.bin` d'Arduino, `ota_data_initial.bin` d'ESP-IDF).
  otaData,

  /// Application.
  app,

  /// Contenu non reconnu : l'adresse doit être donnée à la main.
  unknown,
}

/// Une entrée de la table de partitions.
class EspPartition {
  const EspPartition({required this.type, required this.subtype, required this.offset, required this.size, required this.label});

  /// 0 : application, 1 : données.
  final int type;
  final int subtype;
  final int offset;
  final int size;
  final String label;

  /// Partition d'application plausible : ESP-IDF les aligne sur 64 Ko, après la table de partitions.
  /// Une entrée qui ne l'est pas (table abîmée) n'est pas retenue pour placer l'application.
  bool get isApp => type == 0x00 && offset >= 0x10000 && offset % 0x10000 == 0;

  /// Partition « otadata » (données, sous-type 0), forcément après la table de partitions.
  bool get isOtaData => type == 0x01 && subtype == 0x00 && offset > espPartitionTableOffset;
}

/// Adresse de la table de partitions dans la flash (valeur par défaut d'ESP-IDF et d'Arduino).
const int espPartitionTableOffset = 0x8000;

/// Partition « otadata » du schéma par défaut d'Arduino (`boot_app0.bin`), quand aucune table n'est fournie.
const int espArduinoOtaDataOffset = 0xE000;

/// Partition « otadata » du schéma OTA par défaut d'ESP-IDF (`ota_data_initial.bin`).
const int espIdfOtaDataOffset = 0xD000;

const int _entrySize = 32;

/// Marque `esp_app_desc_t` (0xABCD5432) qui suit l'en-tête de toute application ESP-IDF ou Arduino :
/// un bootloader n'en a pas.
const List<int> _appDescMagic = [0x32, 0x54, 0xCD, 0xAB];

/// Lit les entrées d'une table de partitions (32 octets chacune, marque `0xAA 0x50`) jusqu'à la fin de
/// la table (entrée vide ou somme MD5 `0xEB 0xEB`). Liste vide si [data] n'est pas une table.
List<EspPartition> parsePartitionTable(Uint8List data) {
  final entries = <EspPartition>[];
  final view = ByteData.sublistView(data);
  for (var o = 0; o + _entrySize <= data.length; o += _entrySize) {
    if (data[o] != 0xAA || data[o + 1] != 0x50) break;
    final labelBytes = data.sublist(o + 12, o + 28).takeWhile((b) => b != 0).toList();
    entries.add(EspPartition(
      type: data[o + 2],
      subtype: data[o + 3],
      offset: view.getUint32(o + 4, Endian.little),
      size: view.getUint32(o + 8, Endian.little),
      label: latin1.decode(labelBytes),
    ));
  }
  return entries;
}

/// Ce que le contenu (et, faute de mieux, le nom) d'un fichier dit de lui.
class EspPartGuess {
  const EspPartGuess({required this.role, this.chip, this.offset, this.fromTable = false});

  final EspPartRole role;

  /// Puce visée, quand le fichier est une image (bootloader, application, image complète).
  final EspChip? chip;

  /// Adresse où l'écrire ; nulle si elle ne peut pas être devinée.
  final int? offset;

  /// Vrai si l'adresse vient de la table de partitions fournie avec les autres fichiers.
  final bool fromTable;
}

/// Devine le rôle et l'adresse de [data] (nommé [name]). [table] : la table de partitions fournie avec
/// les autres fichiers, qui donne l'adresse exacte de l'application et des données OTA.
EspPartGuess guessEspPart(String name, Uint8List data, {List<EspPartition> table = const []}) {
  final lower = name.toLowerCase();
  if (data.length >= 2 && data[0] == 0xAA && data[1] == 0x50) {
    return const EspPartGuess(role: EspPartRole.partitionTable, offset: espPartitionTableOffset);
  }

  final image = analyzeEspImage(data);
  if (image != null) {
    if (image.isFullImage) {
      return EspPartGuess(role: EspPartRole.fullImage, chip: image.chip, offset: image.suggestedOffset);
    }
    final hasAppDesc = data.length >= 36 && _listEquals(data.sublist(32, 36), _appDescMagic);
    // Le bootloader doit tenir entre son adresse et la table de partitions.
    final fitsBeforeTable = data.length <= espPartitionTableOffset - image.chip.bootloaderOffset;
    if (!hasAppDesc && fitsBeforeTable) {
      return EspPartGuess(role: EspPartRole.bootloader, chip: image.chip, offset: image.chip.bootloaderOffset);
    }
    final app = table.where((p) => p.isApp).firstOrNull;
    return EspPartGuess(
      role: EspPartRole.app,
      chip: image.chip,
      offset: app?.offset ?? espDefaultAppOffset,
      fromTable: app != null,
    );
  }

  if (lower.contains('boot_app0') || lower.contains('ota_data')) {
    final otaData = table.where((p) => p.isOtaData).firstOrNull;
    final fallback = lower.contains('boot_app0') ? espArduinoOtaDataOffset : espIdfOtaDataOffset;
    return EspPartGuess(role: EspPartRole.otaData, offset: otaData?.offset ?? fallback, fromTable: otaData != null);
  }
  return const EspPartGuess(role: EspPartRole.unknown);
}

/// Un fichier à écrire à une adresse.
class EspFlashPart {
  const EspFlashPart({required this.name, required this.offset, required this.data});

  final String name;
  final int offset;
  final Uint8List data;

  int get end => offset + data.length;
}

/// Premier couple de parties qui se recouvrent en mémoire flash, ou null. L'ordre de [parts] est quelconque.
(EspFlashPart, EspFlashPart)? findOverlap(List<EspFlashPart> parts) {
  final sorted = [...parts]..sort((a, b) => a.offset.compareTo(b.offset));
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i].offset < sorted[i - 1].end) return (sorted[i - 1], sorted[i]);
  }
  return null;
}

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
