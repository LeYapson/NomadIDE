import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/settings.dart';
import '../../l10n/l10n.dart';

/// Vrai dans les tests (voir `test/flutter_test_config.dart`) : le tutoriel ne s'ouvre pas tout seul
/// au premier lancement et ne masque donc pas l'écran testé. Ses propres tests le remettent à faux.
bool debugSkipOnboarding = false;

/// Ouvre le tutoriel par-dessus l'app (premier lancement, ou Réglages → Aide).
Future<void> showOnboarding(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const OnboardingPage()),
    );

/// Prise en main en quatre étapes : ce qu'est NomadIDE, brancher sa carte, les cinq onglets, le premier
/// programme. On peut la passer à tout moment ; elle n'est montrée d'office qu'une fois.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  static const _steps = 4;
  final PageController _pages = PageController();
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int index) => _pages.animateToPage(index, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);

  /// Termine le tutoriel (et ouvre [tab] si demandé). Il ne sera plus montré d'office.
  void _finish({HomeTab? tab}) {
    ref.read(settingsProvider.notifier).setOnboardingDone(true);
    if (tab != null) ref.read(homeTabProvider.notifier).show(tab);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final last = _index == _steps - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(l10n.obProgress(_index + 1, _steps), style: Theme.of(context).textTheme.labelLarge),
                    ),
                  ),
                  TextButton(onPressed: _finish, child: Text(l10n.obSkip)),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  _Step(icon: Icons.developer_board, title: l10n.obWelcomeTitle, children: [Text(l10n.obWelcomeBody)]),
                  _Step(
                    icon: Icons.usb,
                    title: l10n.obPlugTitle,
                    children: [
                      Text(l10n.obPlugBody),
                      const SizedBox(height: 12),
                      _Tip(icon: Icons.cable, text: l10n.obPlugCable),
                    ],
                  ),
                  _Step(
                    icon: Icons.dashboard_outlined,
                    title: l10n.obTabsTitle,
                    children: [
                      _Tip(icon: Icons.terminal, text: l10n.obTabMonitor),
                      _Tip(icon: Icons.memory, text: l10n.obTabPython),
                      _Tip(icon: Icons.code, text: l10n.obTabEditor),
                      _Tip(icon: Icons.bolt, text: l10n.obTabFlash),
                      _Tip(icon: Icons.settings_outlined, text: l10n.obTabSettings),
                    ],
                  ),
                  _Step(
                    icon: Icons.play_circle_outline,
                    title: l10n.obFirstTitle,
                    children: [
                      Text(l10n.obFirstBody),
                      const SizedBox(height: 12),
                      _Tip(icon: Icons.help_outline, text: l10n.obFirstNoFirmware),
                    ],
                  ),
                ],
              ),
            ),
            // Repère visuel de la position ; le texte « Étape n sur 4 » la donne au lecteur d'écran.
            ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _steps; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.all(4),
                      width: i == _index ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _index ? scheme.primary : scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_index > 0)
                    OutlinedButton(onPressed: () => _go(_index - 1), child: Text(l10n.obBack))
                  else
                    const SizedBox.shrink(),
                  if (last)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(onPressed: () => _finish(tab: HomeTab.micropython), child: Text(l10n.obOpenPython)),
                        FilledButton(onPressed: _finish, child: Text(l10n.obStart)),
                      ],
                    )
                  else
                    FilledButton(onPressed: () => _go(_index + 1), child: Text(l10n.obNext)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Une étape : grande icône, titre (annoncé comme titre), contenu qui défile si le texte est agrandi.
class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.title, required this.children});

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, size: 56, color: theme.colorScheme.primary)),
          const SizedBox(height: 16),
          Semantics(header: true, child: Text(title, style: theme.textTheme.headlineSmall)),
          const SizedBox(height: 12),
          DefaultTextStyle.merge(style: theme.textTheme.bodyLarge, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children)),
        ],
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(child: Icon(icon, color: Theme.of(context).colorScheme.primary)),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
