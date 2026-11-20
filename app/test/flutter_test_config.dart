import 'dart:async';

import 'package:nomad_mcu/features/onboarding/tour.dart';
import 'package:nomad_mcu/features/settings/application/update_checker.dart';

/// Exécuté avant chaque fichier de test : la visite guidée du premier lancement ne s'ouvre pas toute seule
/// (il masquerait l'écran testé) et l'app ne cherche pas de mise à jour sur GitHub au démarrage (aucune
/// requête réseau réelle). `onboarding_test.dart` et `update_test.dart` les réactivent.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  debugSkipOnboarding = true;
  debugSkipUpdateCheck = true;
  await testMain();
}
