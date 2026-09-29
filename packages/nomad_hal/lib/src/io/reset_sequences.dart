import '../domain/serial_transport.dart';

/// Séquences de pilotage des lignes DTR/RTS pour redémarrer une carte ou la
/// faire entrer en bootloader sans toucher aux boutons.
///
/// Circuit « auto-reset » classique des cartes ESP32/ESP8266 (2 transistors
/// croisés, DTR → IO0, RTS → EN) :
///
/// | DTR | RTS | EN | IO0 | Effet                                   |
/// |-----|-----|----|-----|-----------------------------------------|
/// |  1  |  1  | 1  |  1  | neutre (état à l'ouverture, cf. pyserial)|
/// |  0  |  0  | 1  |  1  | neutre                                  |
/// |  1  |  0  | 1  |  0  | IO0 bas : boot en mode téléchargement    |
/// |  0  |  1  | 0  |  1  | EN bas : puce maintenue en reset         |
///
/// Le contrôleur USB-Serial-JTAG des ESP32-C3/S3 émule la même table.
extension BoardResetSequences on SerialConnection {
  /// Reset matériel : impulsion sur EN via RTS, avec IO0 haut (boot normal).
  /// Laisse les lignes à DTR=0 / RTS=0 (état neutre).
  Future<void> hardReset({Duration pulse = const Duration(milliseconds: 100)}) async {
    await setDtr(false); // IO0 haut
    await setRts(true); // EN bas → reset
    await Future<void>.delayed(pulse);
    await setRts(false); // EN haut → la puce redémarre normalement
  }

  /// Séquence « ClassicReset » d'esptool : la puce redémarre dans la ROM de
  /// téléchargement (prête pour la synchro SLIP de l'étape 3).
  ///
  /// Le passage DTR=1 puis RTS=0 crée un bref état (1,1). Ça marche parce que
  /// le condensateur sur EN retarde sa remontée de quelques ms. Sur Android,
  /// chaque appel de ligne passe par le canal natif (latence de l'ordre de la
  /// ms). Si la carte ne répond pas, il faut passer en bootloader à la main
  /// (BOOT maintenu + EN).
  Future<void> enterEspBootloader({Duration resetDelay = const Duration(milliseconds: 50)}) async {
    await setDtr(false); // IO0 haut
    await setRts(true); // EN bas, puce en reset
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await setDtr(true); // IO0 bas
    await setRts(false); // EN haut : la ROM lit IO0=0 → mode téléchargement
    await Future<void>.delayed(resetDelay);
    await setDtr(false); // relâche IO0
  }

  /// « 1200 bps touch » (convention Arduino / arduino-pico) : ouvrir à 1200
  /// bauds puis couper DTR fait redémarrer RP2040, SAMD, nRF52… en bootloader
  /// UF2. Ferme la connexion : la carte réapparaît comme un autre périphérique.
  Future<void> touch1200Baud() async {
    await setConfig(config.copyWith(baudRate: 1200));
    await setDtr(false);
    await close();
  }
}
