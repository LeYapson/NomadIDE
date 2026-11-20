import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/settings.dart';
import '../../l10n/generated/app_localizations.dart';

/// Vrai dans les tests (voir `test/flutter_test_config.dart`) : la visite guidée ne s'ouvre pas toute seule
/// au premier lancement et ne masque donc pas l'écran testé. Ses propres tests le remettent à faux.
bool debugSkipOnboarding = false;

/// Les éléments de l'app que la visite peut éclairer.
enum TourTarget { board, connect, navMonitor, navPython, navEditor, navFlash, navSettings }

/// Une clé par élément éclairable. Chaque écran pose la clé sur son widget ; la visite mesure ce qu'elle
/// désigne. Liée au conteneur Riverpod, donc jamais partagée entre deux apps (tests).
class TourTargets {
  final Map<TourTarget, GlobalKey> _keys = {for (final t in TourTarget.values) t: GlobalKey(debugLabel: 'tour-${t.name}')};

  GlobalKey keyOf(TourTarget target) => _keys[target]!;
}

final tourTargetsProvider = Provider<TourTargets>((ref) => TourTargets());

/// Une étape : l'onglet à afficher, l'élément à éclairer (aucun : carte au centre) et ses textes.
class TourStep {
  const TourStep({required this.tab, required this.title, required this.body, this.target, this.interactive = false});

  final HomeTab tab;
  final TourTarget? target;

  /// Vrai : l'élément éclairé reste utilisable (on peut l'essayer). Faux : le toucher passe à l'étape suivante.
  final bool interactive;
  final String Function(AppLocalizations l10n) title;
  final String Function(AppLocalizations l10n) body;
}

/// La visite : bienvenue, brancher la carte, les cinq onglets, le premier programme.
final List<TourStep> tourSteps = [
  TourStep(tab: HomeTab.monitor, title: (l) => l.obWelcomeTitle, body: (l) => l.tourWelcomeBody),
  TourStep(tab: HomeTab.micropython, target: TourTarget.board, interactive: true, title: (l) => l.obPlugTitle, body: (l) => l.tourPlugBody),
  TourStep(tab: HomeTab.monitor, target: TourTarget.navMonitor, title: (l) => l.navMonitor, body: (l) => l.tourMonitorBody),
  TourStep(tab: HomeTab.micropython, target: TourTarget.navPython, title: (l) => l.navMicroPython, body: (l) => l.tourPythonBody),
  TourStep(tab: HomeTab.editor, target: TourTarget.navEditor, title: (l) => l.navEditor, body: (l) => l.tourEditorBody),
  TourStep(tab: HomeTab.flash, target: TourTarget.navFlash, title: (l) => l.navFlash, body: (l) => l.tourFlashBody),
  TourStep(tab: HomeTab.settings, target: TourTarget.navSettings, title: (l) => l.navSettings, body: (l) => l.tourSettingsBody),
  TourStep(tab: HomeTab.micropython, target: TourTarget.connect, interactive: true, title: (l) => l.obFirstTitle, body: (l) => l.tourFirstBody),
];

/// Étape en cours (`null` : pas de visite). Chaque étape affiche son onglet, pour que l'élément éclairé soit
/// celui du vrai écran.
final tourProvider = NotifierProvider<TourController, int?>(TourController.new);

class TourController extends Notifier<int?> {
  @override
  int? build() => null;

  void start() => _show(0);

  void next() {
    final index = state;
    if (index == null) return;
    if (index + 1 >= tourSteps.length) {
      finish();
    } else {
      _show(index + 1);
    }
  }

  /// Étape précédente ; depuis la première, termine la visite (touche « retour » du téléphone).
  void back() {
    final index = state;
    if (index == null) return;
    if (index == 0) {
      finish();
    } else {
      _show(index - 1);
    }
  }

  /// Ferme la visite (terminée ou passée) : elle ne sera plus montrée d'office.
  void finish() {
    if (state == null) return;
    state = null;
    ref.read(settingsProvider.notifier).setOnboardingDone(true);
  }

  void _show(int index) {
    state = index;
    ref.read(homeTabProvider.notifier).show(tourSteps[index].tab);
  }
}
