import 'dart:typed_data';

import 'esp_loader.dart';

/// Ce que l'en-tête d'un fichier `.bin` révèle de son contenu.
class EspImageInfo {
  const EspImageInfo({required this.chip, required this.isFullImage, required this.suggestedOffset});

  /// Puce pour laquelle le fichier est construit.
  final EspChip chip;

  /// Vrai pour une image complète (bootloader, table de partitions et application, comme le firmware
  /// officiel de MicroPython) ; faux pour une application seule.
  final bool isFullImage;

  /// Adresse où écrire le fichier : celle du bootloader pour une image complète, 0x10000 (première
  /// partition d'application de la table par défaut) pour une application.
  final int suggestedOffset;
}

/// Adresse de la première application dans la table de partitions par défaut d'ESP-IDF et de MicroPython.
const int espDefaultAppOffset = 0x10000;

/// Adresse de la table de partitions dans la flash.
const int _partitionTableAddress = 0x8000;

const int _imageMagic = 0xE9;

/// Numéro de puce du champ « chip_id » de l'en-tête étendu d'une image.
const Map<int, EspChip> _chipIds = {
  0x0000: EspChip.esp32,
  0x0002: EspChip.esp32s2,
  0x0005: EspChip.esp32c3,
  0x0009: EspChip.esp32s3,
  0x000D: EspChip.esp32c6,
  0x0010: EspChip.esp32h2,
};

/// Analyse [data] et renvoie ses caractéristiques, ou `null` si ce n'est pas reconnaissable comme une
/// image ESP32 (fichier quelconque, image d'ESP8266 dont l'en-tête est plus court, données brutes…).
///
/// - L'en-tête commence par `0xE9` ; l'en-tête étendu (24 octets) donne la puce à l'offset 12, et ses
///   octets réservés (19 à 22) sont à zéro, ce qui écarte les images d'ESP8266 (dont l'en-tête est plus court).
/// - Une image complète contient la table de partitions (marque `0xAA 0x50`) à l'endroit où elle
///   se retrouve dans la flash : 0x8000 moins l'adresse du bootloader.
EspImageInfo? analyzeEspImage(Uint8List data) {
  if (data.length < 24 || data[0] != _imageMagic) return null;
  final view = ByteData.sublistView(data);
  final chip = _chipIds[view.getUint16(12, Endian.little)];
  if (chip == null) return null;
  // Octets 19 à 22 : réservés, à zéro (juste avant, les révisions min. et max. de la puce).
  for (var i = 19; i < 23; i++) {
    if (data[i] != 0) return null;
  }
  if (data[23] > 1) return null; // « hash append » : 0 ou 1

  final bootloader = chip.bootloaderOffset;
  final tableInFile = _partitionTableAddress - bootloader;
  final full = data.length > tableInFile + 1 && data[tableInFile] == 0xAA && data[tableInFile + 1] == 0x50;
  return EspImageInfo(chip: chip, isFullImage: full, suggestedOffset: full ? bootloader : espDefaultAppOffset);
}
