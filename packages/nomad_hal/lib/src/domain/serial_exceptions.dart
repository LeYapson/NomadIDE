/// Cause précise d'une erreur de la HAL, pour que l'application affiche le
/// message dans la langue de l'utilisateur (les [SerialException.message] sont
/// des repères en français pour les journaux de développement).
enum SerialErrorCode {
  other,

  /// La plateforme n'a pas d'accès série (iOS…). Paramètre : `platform`.
  unsupportedPlatform,

  /// Le périphérique n'est plus là. Paramètre : `device`.
  deviceNotFound,

  /// Port introuvable. Paramètre : `path`.
  portNotFound,

  /// Android : permission USB refusée, ou puce non prise en charge.
  usbPermissionDenied,

  /// Linux : accès refusé au port. Paramètres : `path`, `os`.
  portPermissionDenied,

  /// Ouverture impossible. Paramètres : `path` ou `device`, et `os` (message du système) s'il existe.
  openFailed,

  /// Android : création du port USB impossible.
  usbPortCreateFailed,

  /// Android : flux de réception indisponible.
  usbStreamUnavailable,

  /// Le périphérique est déjà ouvert. Paramètre : `device`.
  alreadyOpen,

  /// Opération sur une connexion fermée.
  connectionClosed,

  /// Le port a été fermé pendant une lecture.
  closedDuringRead,

  /// Erreur de lecture sur le port.
  readFailed,

  /// Pas de réponse à temps. Paramètre : `timeoutMs`.
  noResponse,

  /// Échec d'une opération sur un port ouvert. Paramètres : `operation` ([SerialOperation]), `device`.
  operationFailed,

  /// 1,5 bit de stop non géré par libserialport.
  unsupportedStopBits,

  /// Écriture interrompue faute de place dans le tampon. Paramètres : `remaining` (octets), `seconds`.
  writeTimeout,
}

/// Opération en échec dans [SerialErrorCode.operationFailed].
enum SerialOperation { write, configure, dtr, rts }

/// Hiérarchie d'erreurs de la HAL série.
///
/// `sealed` : l'UI peut faire un `switch` exhaustif pour afficher un message
/// adapté (permission refusée, port occupé, carte débranchée…).
sealed class SerialException implements Exception {
  const SerialException(
    this.message, {
    this.cause,
    this.code = SerialErrorCode.other,
    this.params = const {},
  });

  /// Repère en français pour les journaux ; l'interface s'appuie sur [code] et [params].
  final String message;

  /// Erreur d'origine (PlatformException, SerialPortError…), pour les logs.
  final Object? cause;

  final SerialErrorCode code;

  /// Valeurs à insérer dans le message localisé (voir [SerialErrorCode]).
  final Map<String, Object?> params;

  @override
  String toString() => cause == null ? '$runtimeType: $message' : '$runtimeType: $message (cause : $cause)';
}

/// La plateforme courante ne permet pas l'accès série (ex. iOS).
final class SerialUnsupportedException extends SerialException {
  const SerialUnsupportedException(super.message, {super.cause, super.code, super.params});
}

/// Le périphérique demandé n'est plus présent.
final class SerialDeviceNotFoundException extends SerialException {
  const SerialDeviceNotFoundException(super.message, {super.cause, super.code, super.params});
}

/// L'utilisateur (Android) ou l'OS (groupe `dialout` sous Linux) refuse l'accès.
final class SerialPermissionException extends SerialException {
  const SerialPermissionException(super.message, {super.cause, super.code, super.params});
}

/// Ouverture impossible (port déjà utilisé, pilote absent…).
final class SerialOpenException extends SerialException {
  const SerialOpenException(super.message, {super.cause, super.code, super.params});
}

/// Échec d'une opération sur un port ouvert (écriture, configuration, lignes de contrôle).
final class SerialIoException extends SerialException {
  const SerialIoException(super.message, {super.cause, super.code, super.params});
}

/// Opération tentée sur une connexion fermée.
final class SerialClosedException extends SerialException {
  const SerialClosedException(super.message, {super.cause, super.code, super.params});
}

/// La carte n'a pas répondu dans le délai imparti.
final class SerialTimeoutException extends SerialException {
  const SerialTimeoutException(super.message, {super.cause, super.code, super.params});
}
