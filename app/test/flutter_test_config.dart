import 'dart:async';

import 'package:nomad_mcu/features/onboarding/onboarding_page.dart';

/// Exécuté avant chaque fichier de test : le tutoriel du premier lancement ne s'ouvre pas tout seul,
/// sinon il masquerait l'écran testé. `onboarding_test.dart` le réactive pour ses propres tests.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  debugSkipOnboarding = true;
  await testMain();
}
