
import 'package:flutter/foundation.dart';
import 'package:nomad_hal/nomad_hal.dart';

import '../domain/log_entry.dart';

enum ConnectionStatus { disconnected, connecting, connected }

enum LineEnding {
  none('Aucune', []),
  lf('LF', [0x0A]),
  cr('CR', [0x0D]),
  crlf('CR+LF', [0x0D, 0x0A]);

  const LineEnding(this.label, this.bytes);

  final String label;
  final List<int> bytes;
}

const Object _unset = Object();

/// État immuable du moniteur série, exposé à l'UI.
@immutable
class SerialMonitorState {
  const SerialMonitorState({
    this.transportKind,
    this.devices = const [],
    this.selectedDevice,
    this.config = const SerialConfig(),
    this.status = ConnectionStatus.disconnected,
    this.errorMessage,
    this.entries = const [],
    this.partialLine,
    // Le REPL MicroPython attend un simple \r (comme mpremote / Thonny).
    this.lineEnding = LineEnding.cr,
    this.hexView = false,
    this.showTimestamps = true,
    this.dtr = false,
    this.rts = false,
    this.rxBytes = 0,
    this.txBytes = 0,
  });

  final TransportKind? transportKind;
  final List<SerialDeviceInfo> devices;
  final SerialDeviceInfo? selectedDevice;
  final SerialConfig config;
  final ConnectionStatus status;

  /// Dernière erreur à signaler (SnackBar) ; null une fois résolue.
  final String? errorMessage;

  /// Lignes complètes, plafonnées à [SerialMonitorController.maxEntries].
  final List<LogEntry> entries;

  /// Ligne en cours de réception, sans `\n` (ex. l'invite `>>> `).
  final Uint8List? partialLine;

  final LineEnding lineEnding;
  final bool hexView;
  final bool showTimestamps;
  final bool dtr;
  final bool rts;
  final int rxBytes;
  final int txBytes;

  bool get isConnected => status == ConnectionStatus.connected;

  SerialMonitorState copyWith({
    TransportKind? transportKind,
    List<SerialDeviceInfo>? devices,
    Object? selectedDevice = _unset,
    SerialConfig? config,
    ConnectionStatus? status,
    Object? errorMessage = _unset,
    List<LogEntry>? entries,
    Object? partialLine = _unset,
    LineEnding? lineEnding,
    bool? hexView,
    bool? showTimestamps,
    bool? dtr,
    bool? rts,
    int? rxBytes,
    int? txBytes,
  }) {
    return SerialMonitorState(
      transportKind: transportKind ?? this.transportKind,
      devices: devices ?? this.devices,
      selectedDevice: identical(selectedDevice, _unset) ? this.selectedDevice : selectedDevice as SerialDeviceInfo?,
      config: config ?? this.config,
      status: status ?? this.status,
      errorMessage: identical(errorMessage, _unset) ? this.errorMessage : errorMessage as String?,
      entries: entries ?? this.entries,
      partialLine: identical(partialLine, _unset) ? this.partialLine : partialLine as Uint8List?,
      lineEnding: lineEnding ?? this.lineEnding,
      hexView: hexView ?? this.hexView,
      showTimestamps: showTimestamps ?? this.showTimestamps,
      dtr: dtr ?? this.dtr,
      rts: rts ?? this.rts,
      rxBytes: rxBytes ?? this.rxBytes,
      txBytes: txBytes ?? this.txBytes,
    );
  }
}
