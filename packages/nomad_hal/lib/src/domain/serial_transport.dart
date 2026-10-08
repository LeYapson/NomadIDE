import 'dart:async';

import 'package:flutter/foundation.dart';

import 'serial_config.dart';
import 'serial_device_info.dart';

enum DeviceEventType { attached, detached }

/// Branchement / débranchement à chaud d'un périphérique.
@immutable
class DeviceEvent {
  const DeviceEvent(this.type, this.deviceId, [this.device]);

  final DeviceEventType type;
  final String deviceId;
  final SerialDeviceInfo? device;

  @override
  String toString() => 'DeviceEvent(${type.name}, $deviceId)';
}

enum DisconnectReason {
  /// [SerialConnection.close] a été appelé.
  closedByUser,

  /// Le câble a été débranché ou la carte a disparu (reset USB, passage en BOOTSEL…).
  deviceLost,

  /// Erreur d'E/S irrécupérable.
  error,
}

/// Point d'entrée de la HAL pour une plateforme donnée : énumère les
/// périphériques, signale le hotplug et ouvre des connexions.
///
/// Implémentations : Android (USB Host/OTG), desktop (libserialport),
/// simulateur (tests, UI sans matériel), non supporté (iOS).
/// À venir : BLE (Nordic UART), WebREPL (WebSocket).
/// Famille de transport, pour que l'interface en affiche le nom dans la langue de l'utilisateur.
enum TransportKind { desktop, androidUsb, simulated, unsupported }

abstract interface class SerialTransport {
  TransportKind get kind;

  /// Nom lisible du transport, affiché dans l'UI.
  String get name;

  /// Faux si la plateforme ne permet aucun accès série.
  bool get isSupported;

  Future<List<SerialDeviceInfo>> listDevices();

  /// Flux broadcast des branchements / débranchements.
  Stream<DeviceEvent> get deviceEvents;

  /// Ouvre [device].
  ///
  /// [dtr] / [rts] : état initial des lignes de contrôle. La valeur par défaut
  /// (les deux actives) est celle de pyserial :
  ///  * les puces CDC-ACM (RP2040, ESP32-S3 natif…) n'émettent souvent rien tant que DTR est inactif ;
  ///  * sur le circuit auto-reset des ESP32, DTR=RTS=1 est un état neutre (pas de reset).
  Future<SerialConnection> open(
    SerialDeviceInfo device, {
    SerialConfig config = const SerialConfig(),
    bool dtr = true,
    bool rts = true,
  });

  Future<void> dispose();
}

/// Connexion ouverte vers une carte.
abstract interface class SerialConnection {
  SerialDeviceInfo get device;
  SerialConfig get config;
  bool get isOpen;

  /// État courant des lignes de contrôle (tel que positionné par l'hôte).
  bool get dtr;
  bool get rts;

  /// Flux **broadcast** des octets reçus, livrés par chunks de taille arbitraire.
  /// Un octet émis sans abonné est perdu : abonnez-vous avant d'envoyer une commande.
  Stream<Uint8List> get input;

  /// Se complète une seule fois, à la fin de la connexion, avec sa cause.
  Future<DisconnectReason> get done;

  Future<void> write(Uint8List data);

  /// Change les paramètres de ligne à chaud (ex. passage à 921600 bauds pour le flash).
  Future<void> setConfig(SerialConfig config);

  Future<void> setDtr(bool value);
  Future<void> setRts(bool value);

  Future<void> close();
}
