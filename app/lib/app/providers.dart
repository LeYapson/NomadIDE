import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_hal/nomad_hal.dart';

/// `--dart-define=NOMAD_FAKE_SERIAL=true` : carte simulée (dev UI sans matériel, démo iOS).
const bool kSimulateSerial = bool.fromEnvironment('NOMAD_FAKE_SERIAL');

/// Transport série de la plateforme : point d'injection unique de la HAL.
///
/// Dans les tests : `serialTransportProvider.overrideWithValue(FakeSerialTransport())`.
final serialTransportProvider = Provider<SerialTransport>((ref) {
  final transport = createPlatformTransport(simulate: kSimulateSerial);
  ref.onDispose(transport.dispose);
  return transport;
});
