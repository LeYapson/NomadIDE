import 'package:flutter/foundation.dart';

enum Parity {
  none('N'),
  odd('O'),
  even('E'),
  mark('M'),
  space('S');

  const Parity(this.symbol);

  final String symbol;
}

enum StopBits {
  one('1'),
  onePointFive('1.5'),
  two('2');

  const StopBits(this.symbol);

  final String symbol;
}

enum FlowControl { none, rtsCts, xonXoff }

/// Paramètres de ligne série (indépendants de la plateforme).
@immutable
class SerialConfig {
  const SerialConfig({
    this.baudRate = 115200,
    this.dataBits = 8,
    this.parity = Parity.none,
    this.stopBits = StopBits.one,
    this.flowControl = FlowControl.none,
  })  : assert(baudRate > 0),
        assert(dataBits >= 5 && dataBits <= 8);

  final int baudRate;
  final int dataBits;
  final Parity parity;
  final StopBits stopBits;
  final FlowControl flowControl;

  /// Débits proposés dans l'UI. 74880 = débit de la ROM de boot ESP8266.
  static const List<int> standardBaudRates = [
    300, 1200, 2400, 4800, 9600, 19200, 38400, 57600, 74880, //
    115200, 230400, 460800, 921600, 1500000, 2000000,
  ];

  SerialConfig copyWith({
    int? baudRate,
    int? dataBits,
    Parity? parity,
    StopBits? stopBits,
    FlowControl? flowControl,
  }) {
    return SerialConfig(
      baudRate: baudRate ?? this.baudRate,
      dataBits: dataBits ?? this.dataBits,
      parity: parity ?? this.parity,
      stopBits: stopBits ?? this.stopBits,
      flowControl: flowControl ?? this.flowControl,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SerialConfig &&
      other.baudRate == baudRate &&
      other.dataBits == dataBits &&
      other.parity == parity &&
      other.stopBits == stopBits &&
      other.flowControl == flowControl;

  @override
  int get hashCode => Object.hash(baudRate, dataBits, parity, stopBits, flowControl);

  /// Notation usuelle, ex. « 115200 8N1 ».
  @override
  String toString() => '$baudRate $dataBits${parity.symbol}${stopBits.symbol}';
}
