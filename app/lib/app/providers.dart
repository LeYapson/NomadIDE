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

enum HomeTab { monitor, micropython, editor }

/// Onglet actif de la coque : les fonctionnalités s'y renvoient mutuellement
/// (ex. ouvrir un fichier de la carte dans l'éditeur).
final homeTabProvider = NotifierProvider<HomeTabController, HomeTab>(HomeTabController.new);

class HomeTabController extends Notifier<HomeTab> {
  @override
  HomeTab build() => HomeTab.monitor;

  void show(HomeTab tab) => state = tab;
}
