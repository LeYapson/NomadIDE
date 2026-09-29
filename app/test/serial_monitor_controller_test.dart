import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:nomad_mcu/app/providers.dart';
import 'package:nomad_mcu/features/serial_monitor/application/serial_monitor_controller.dart';
import 'package:nomad_mcu/features/serial_monitor/application/serial_monitor_state.dart';
import 'package:nomad_mcu/features/serial_monitor/domain/log_entry.dart';

void main() {
  late FakeSerialTransport transport;
  late ProviderContainer container;

  setUp(() {
    transport = FakeSerialTransport();
    container = ProviderContainer(overrides: [serialTransportProvider.overrideWithValue(transport)]);
    container.listen(serialMonitorProvider, (previous, next) {}); // garde le provider actif
  });

  tearDown(() => container.dispose());

  SerialMonitorState state() => container.read(serialMonitorProvider);
  SerialMonitorController controller() => container.read(serialMonitorProvider.notifier);
  Iterable<String> rxTexts() => state().entries.where((e) => e.kind == LogKind.rx).map((e) => e.text);
  // Laisse passer la livraison du simulateur (5 ms) et le regroupement du ViewModel (50 ms).
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 150));

  test('connexion : la bannière MicroPython et l’invite sont affichées', () async {
    await controller().refreshDevices();
    expect(state().selectedDevice, FakeSerialTransport.defaultDevice);

    await controller().connect();
    expect(state().status, ConnectionStatus.connected);
    expect(state().dtr && state().rts, isTrue);

    await settle();
    expect(rxTexts(), contains(startsWith('MicroPython')));
    expect(state().partialLine, isNotNull); // « >>> » sans fin de ligne
  });

  test('envoi d’une expression : TX journalisé et résultat reçu', () async {
    await controller().refreshDevices();
    await controller().connect();
    await settle();

    await controller().send('6*7');
    await settle();

    expect(state().entries.where((e) => e.kind == LogKind.tx).map((e) => e.text), contains('6*7'));
    expect(rxTexts(), contains('42'));
    expect(state().txBytes, 4); // "6*7" + \r
  });

  test('débranchement : retour à l’état déconnecté avec un message d’erreur', () async {
    await controller().refreshDevices();
    await controller().connect();

    transport.simulateDetach(FakeSerialTransport.defaultDevice.id);
    await settle();

    expect(state().status, ConnectionStatus.disconnected);
    expect(state().errorMessage, isNotNull);
    expect(state().devices, isEmpty);
  });
}
