/// Hiérarchie d'erreurs de la HAL série.
///
/// `sealed` : l'UI peut faire un `switch` exhaustif pour afficher un message
/// adapté (permission refusée, port occupé, carte débranchée…).
sealed class SerialException implements Exception {
  const SerialException(this.message, {this.cause});

  /// Message lisible, destiné à l'utilisateur final.
  final String message;

  /// Erreur d'origine (PlatformException, SerialPortError…), pour les logs.
  final Object? cause;

  @override
  String toString() => cause == null ? '$runtimeType: $message' : '$runtimeType: $message (cause : $cause)';
}

/// La plateforme courante ne permet pas l'accès série (ex. iOS).
final class SerialUnsupportedException extends SerialException {
  const SerialUnsupportedException(super.message, {super.cause});
}

/// Le périphérique demandé n'est plus présent.
final class SerialDeviceNotFoundException extends SerialException {
  const SerialDeviceNotFoundException(super.message, {super.cause});
}

/// L'utilisateur (Android) ou l'OS (groupe `dialout` sous Linux) refuse l'accès.
final class SerialPermissionException extends SerialException {
  const SerialPermissionException(super.message, {super.cause});
}

/// Ouverture impossible (port déjà utilisé, pilote absent…).
final class SerialOpenException extends SerialException {
  const SerialOpenException(super.message, {super.cause});
}

/// Échec d'une opération sur un port ouvert (écriture, configuration, lignes de contrôle).
final class SerialIoException extends SerialException {
  const SerialIoException(super.message, {super.cause});
}

/// Opération tentée sur une connexion fermée.
final class SerialClosedException extends SerialException {
  const SerialClosedException(super.message, {super.cause});
}

/// La carte n'a pas répondu dans le délai imparti.
final class SerialTimeoutException extends SerialException {
  const SerialTimeoutException(super.message, {super.cause});
}
