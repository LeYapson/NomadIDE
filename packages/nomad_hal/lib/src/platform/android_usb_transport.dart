import 'dart:async';
import 'dart:typed_data';

import 'package:usb_serial/usb_serial.dart';

import '../domain/serial_config.dart';
import '../domain/serial_device_info.dart';
import '../domain/serial_exceptions.dart';
import '../domain/serial_transport.dart';
import '../domain/usb_chip.dart';
import 'base_serial_connection.dart';

/// Transport Android : API USB Host (OTG) via le plugin `usb_serial`.
///
/// Android n'expose pas `/dev/ttyUSB*` aux applications : on passe par
/// `UsbManager`, avec une permission accordée par l'utilisateur, et des pilotes
/// userland (CDC-ACM, FTDI, CP210x, CH34x, PL2303).
///
/// L'intent-filter `USB_DEVICE_ATTACHED` du manifeste (voir
/// `app/android/app/src/main/AndroidManifest.xml`) permet à l'utilisateur de
/// cocher « toujours ouvrir avec NomadMCU » et d'éviter la popup à chaque branchement.
class AndroidUsbSerialTransport implements SerialTransport {
  final Map<String, AndroidUsbSerialConnection> _open = {};
  StreamSubscription<DeviceEvent>? _detachWatcher;

  @override
  String get name => 'USB OTG (Android)';

  @override
  bool get isSupported => true;

  @override
  Future<List<SerialDeviceInfo>> listDevices() async {
    final devices = await UsbSerial.listDevices();
    return [for (final device in devices) _toInfo(device)];
  }

  @override
  Stream<DeviceEvent> get deviceEvents {
    final source = UsbSerial.usbEventStream;
    if (source == null) return const Stream<DeviceEvent>.empty();
    return source.map(_toEvent).where((e) => e != null).map((e) => e!);
  }

  @override
  Future<SerialConnection> open(
    SerialDeviceInfo device, {
    SerialConfig config = const SerialConfig(),
    bool dtr = true,
    bool rts = true,
  }) async {
    final usbDevice = await _find(device.id);
    if (usbDevice == null) {
      throw SerialDeviceNotFoundException("${device.displayName} n'est plus connecté.");
    }

    // create() affiche la demande de permission Android si nécessaire
    // et renvoie null si l'utilisateur refuse.
    final driver = _driverName(device.chip.driver);
    UsbPort? port;
    try {
      port = await usbDevice.create(driver);
      // Puces non référencées (ex. composite CDC + JTAG) : repli explicite en CDC-ACM.
      if (port == null && driver != UsbSerial.CDC) {
        port = await usbDevice.create(UsbSerial.CDC);
      }
    } catch (e) {
      throw SerialOpenException('Création du port USB impossible.', cause: e);
    }
    if (port == null) {
      throw const SerialPermissionException(
        'Permission USB refusée, ou puce USB-série non prise en charge.',
      );
    }

    var opened = false;
    try {
      opened = await port.open();
    } catch (e) {
      throw SerialOpenException("Ouverture de ${device.displayName} impossible.", cause: e);
    }
    if (!opened) {
      throw SerialOpenException("Ouverture de ${device.displayName} impossible.");
    }

    final connection = AndroidUsbSerialConnection._(
      device: device,
      config: config,
      port: port,
      onClosed: () => _open.remove(device.id),
    );
    try {
      await connection._init(dtr: dtr, rts: rts);
    } catch (_) {
      await connection.close();
      rethrow;
    }
    _open[device.id] = connection;
    _watchDetach();
    return connection;
  }

  @override
  Future<void> dispose() async {
    await _detachWatcher?.cancel();
    _detachWatcher = null;
    for (final connection in [..._open.values]) {
      await connection.close();
    }
  }

  /// Le flux d'entrée de `usb_serial` ne se termine pas toujours au débranchement :
  /// on s'appuie en plus sur l'événement système `USB_DEVICE_DETACHED`.
  void _watchDetach() {
    _detachWatcher ??= deviceEvents.listen((event) {
      if (event.type == DeviceEventType.detached) _open[event.deviceId]?._onDetached();
    });
  }

  Future<UsbDevice?> _find(String id) async {
    for (final device in await UsbSerial.listDevices()) {
      if (_idOf(device) == id) return device;
    }
    return null;
  }

  static String _idOf(UsbDevice device) => 'usb:${device.deviceId}';

  static SerialDeviceInfo _toInfo(UsbDevice device) {
    final chip = UsbChip.identify(device.vid, device.pid);
    final productName = device.productName?.trim();
    return SerialDeviceInfo(
      id: _idOf(device),
      displayName: (productName != null && productName.isNotEmpty) ? productName : chip.label,
      systemPath: device.deviceName,
      vendorId: device.vid,
      productId: device.pid,
      manufacturer: device.manufacturerName,
      product: device.productName,
      serialNumber: device.serial,
    );
  }

  static DeviceEvent? _toEvent(UsbEvent event) {
    final device = event.device;
    final info = device == null ? null : _toInfo(device);
    final id = info?.id ?? '';
    if (event.event == UsbEvent.ACTION_USB_ATTACHED) {
      return DeviceEvent(DeviceEventType.attached, id, info);
    }
    if (event.event == UsbEvent.ACTION_USB_DETACHED) {
      return DeviceEvent(DeviceEventType.detached, id, info);
    }
    return null;
  }

  /// Chaîne vide = auto-détection par la bibliothèque native.
  static String _driverName(UsbSerialDriver driver) => switch (driver) {
        UsbSerialDriver.ftdi => UsbSerial.FTDI,
        UsbSerialDriver.cp210x => UsbSerial.CP210x,
        UsbSerialDriver.ch34x => UsbSerial.CH34x,
        UsbSerialDriver.pl2303 => UsbSerial.PL2303,
        UsbSerialDriver.cdcAcm => UsbSerial.CDC,
        UsbSerialDriver.notSerial || UsbSerialDriver.unknown => '',
      };
}

class AndroidUsbSerialConnection extends BaseSerialConnection {
  AndroidUsbSerialConnection._({
    required super.device,
    required super.config,
    required UsbPort port,
    required void Function() onClosed,
  })  : _port = port,
        _onClosed = onClosed;

  final UsbPort _port;
  final void Function() _onClosed;
  StreamSubscription<Uint8List>? _subscription;

  Future<void> _init({required bool dtr, required bool rts}) async {
    await applyConfigNative(config);
    // DTR avant RTS : on évite l'état transitoire (DTR=0, RTS=1) qui mettrait un ESP32 en reset.
    await setDtr(dtr);
    await setRts(rts);

    final stream = _port.inputStream;
    if (stream == null) {
      throw const SerialOpenException('Flux de réception USB indisponible.');
    }
    _subscription = stream.listen(
      emitData,
      onError: (Object error) => reportLost(DisconnectReason.error, error),
      onDone: () => reportLost(DisconnectReason.deviceLost),
    );
  }

  void _onDetached() => reportLost(DisconnectReason.deviceLost);

  @override
  Future<void> applyConfigNative(SerialConfig config) async {
    await _port.setPortParameters(
      config.baudRate,
      config.dataBits,
      switch (config.stopBits) {
        StopBits.one => UsbPort.STOPBITS_1,
        StopBits.onePointFive => UsbPort.STOPBITS_1_5,
        StopBits.two => UsbPort.STOPBITS_2,
      },
      switch (config.parity) {
        Parity.none => UsbPort.PARITY_NONE,
        Parity.odd => UsbPort.PARITY_ODD,
        Parity.even => UsbPort.PARITY_EVEN,
        Parity.mark => UsbPort.PARITY_MARK,
        Parity.space => UsbPort.PARITY_SPACE,
      },
    );
    await _port.setFlowControl(switch (config.flowControl) {
      FlowControl.none => UsbPort.FLOW_CONTROL_OFF,
      FlowControl.rtsCts => UsbPort.FLOW_CONTROL_RTS_CTS,
      FlowControl.xonXoff => UsbPort.FLOW_CONTROL_XON_XOFF,
    });
  }

  @override
  Future<void> setDtrNative(bool value) => _port.setDTR(value);

  @override
  Future<void> setRtsNative(bool value) => _port.setRTS(value);

  @override
  Future<void> writeNative(Uint8List data) => _port.write(data);

  @override
  Future<void> closeNative() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _port.close();
    } finally {
      _onClosed();
    }
  }
}
