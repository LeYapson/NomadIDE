import 'dart:async';

import 'package:nomad_mcu/features/onboarding/onboarding_page.dart';
import 'package:nomad_mcu/features/settings/application/update_checker.dart';

/// Exécuté avant chaque fichier de test : le tutoriel du premier lancement ne s'ouvre pas tout seul
/// (il masquerait l'écran testé) et l'app ne cherche pas de mise à jour sur GitHub au démarrage (aucune
/// requête réseau réelle). `onboarding_test.dart` et `update_test.dart` les réactivent.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  debugSkipOnboarding = true;
  debugSkipUpdateCheck = true;
  await testMain();
}
