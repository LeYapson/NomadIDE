import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_protocols/nomad_protocols.dart';

import '../features/projects/data/storage_exception.dart';
import 'generated/app_localizations.dart';

/// Message pour [error], dans la langue de [l10n], quelle que soit sa famille.
String errorMessage(AppLocalizations l10n, Object error) => switch (error) {
      SerialException() => serialErrorMessage(l10n, error),
      ProtocolException() => protocolErrorMessage(l10n, error),
      StorageException() => storageErrorMessage(l10n, error),
      _ => '$error',
    };

String serialErrorMessage(AppLocalizations l, SerialException e) {
  final p = e.params;
  String text(String key) => '${p[key] ?? ''}';
  int number(String key) => (p[key] as int?) ?? 0;
  String os() => (p['os'] as String?) ?? l.errUnknownOsError;
  return switch (e.code) {
    SerialErrorCode.unsupportedPlatform =>
      text('platform') == 'ios' ? l.errSerialUnsupportedIos : l.errSerialUnsupportedPlatform(text('platform')),
    SerialErrorCode.deviceNotFound => l.errDeviceNotFound(text('device')),
    SerialErrorCode.portNotFound => l.errPortNotFound(text('path')),
    SerialErrorCode.usbPermissionDenied => l.errUsbPermissionDenied,
    SerialErrorCode.portPermissionDenied => l.errPortPermissionDenied(text('path'), os()),
    SerialErrorCode.openFailed =>
      p.containsKey('path') ? l.errOpenFailedPath(text('path'), os()) : l.errOpenFailedDevice(text('device')),
    SerialErrorCode.usbPortCreateFailed => l.errUsbPortCreateFailed,
    SerialErrorCode.usbStreamUnavailable => l.errUsbStreamUnavailable,
    SerialErrorCode.alreadyOpen => l.errAlreadyOpen(text('device')),
    SerialErrorCode.connectionClosed => l.errConnectionClosed,
    SerialErrorCode.closedDuringRead => l.errClosedDuringRead,
    SerialErrorCode.readFailed => l.errReadFailed,
    SerialErrorCode.noResponse => l.errNoResponse(number('timeoutMs')),
    SerialErrorCode.operationFailed => switch (p['operation']) {
        SerialOperation.write => l.errOperationWrite(text('device')),
        SerialOperation.configure => l.errOperationConfigure(text('device')),
        SerialOperation.dtr => l.errOperationDtr(text('device')),
        SerialOperation.rts => l.errOperationRts(text('device')),
        _ => l.errSerialOther(e.message),
      },
    SerialErrorCode.unsupportedStopBits => l.errUnsupportedStopBits,
    SerialErrorCode.writeTimeout => l.errWriteTimeout(number('remaining'), number('seconds')),
    SerialErrorCode.other => l.errSerialOther(e.message),
  };
}

String protocolErrorMessage(AppLocalizations l, ProtocolException e) {
  final p = e.params;
  String text(String key) => '${p[key] ?? ''}';
  int number(String key) => (p[key] as int?) ?? 0;
  return switch (e.code) {
    ProtocolErrorCode.linkReadFailed => l.errLinkReadFailed,
    ProtocolErrorCode.linkClosed => l.errLinkClosed,
    ProtocolErrorCode.noResponse => l.errNoResponse(number('timeoutMs')),
    ProtocolErrorCode.rawReplNotEntered => l.errRawReplNotEntered(number('attempts')),
    ProtocolErrorCode.programTimeout => l.errProgramTimeout(number('timeoutMs')),
    ProtocolErrorCode.busy => l.errBusy,
    ProtocolErrorCode.notActive => l.errNotActive,
    ProtocolErrorCode.sessionBroken => l.errSessionBroken,
    ProtocolErrorCode.unexpectedAck => l.errUnexpectedAck(text('hex')),
    ProtocolErrorCode.unexpectedCrcReply => l.errUnexpectedCrcReply(text('reply')),
    ProtocolErrorCode.integrityMismatch =>
      l.errIntegrity(text('path'), number('expectedSize'), number('actualSize')),
    // Dernière ligne de la trace Python : c'est la carte qui parle, ce texte n'est pas traduit.
    ProtocolErrorCode.remoteError => e.message,
    ProtocolErrorCode.espSyncFailed => l.errEspSyncFailed(number('attempts')),
    ProtocolErrorCode.espRomError => l.errEspRom(text('command'), text('error')),
    ProtocolErrorCode.espBadPacket => l.errEspBadPacket(text('hex')),
    ProtocolErrorCode.espVerifyFailed => l.errEspVerifyFailed(text('expected'), text('actual')),
    ProtocolErrorCode.other => l.errProtocolOther(e.message),
  };
}

String storageErrorMessage(AppLocalizations l, StorageException e) {
  final name = e.name == null ? '' : '« ${e.name} »';
  return switch (e.error) {
    StorageError.invalidName => l.errStorageInvalidName(name),
    StorageError.alreadyExists => l.errStorageAlreadyExists(name),
    StorageError.notFound => l.errStorageNotFound(name),
    StorageError.outsideProject => l.errStorageOutsideProject(name),
    StorageError.io => l.errStorageIo(name, '${e.cause ?? l.errUnknownOsError}'),
  };
}

/// Nom d'un type de transport, dans la langue de l'utilisateur.
String transportLabel(AppLocalizations l, TransportKind kind) => switch (kind) {
      TransportKind.desktop => l.transportDesktop,
      TransportKind.androidUsb => l.transportAndroidUsb,
      TransportKind.simulated => l.transportSimulated,
      TransportKind.unsupported => l.transportUnsupported,
    };
