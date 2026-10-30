import 'package:flutter/material.dart';

/// Pourcentage annoncé au lecteur d'écran : par paliers de 25 % (0, 25, 50, 75, 100). Annoncer chaque
/// pourcent le rendrait inutilisable ; un palier suffit pour savoir où en est l'opération.
int announcedPercent(double? fraction) => (((fraction ?? 0).clamp(0.0, 1.0) * 4).floor() * 25).clamp(0, 100);

/// Texte d'une phase en cours et barre de progression. [value] nul : durée inconnue (barre sans fin).
///
/// [spokenLabel] est ce que lit le lecteur d'écran (région « vivante » : un changement est annoncé tout
/// seul). Sans lui, le texte visible est lu tel quel. Les écrans lui donnent le même texte avec un
/// pourcentage arrondi par [announcedPercent], pour n'annoncer que les paliers.
class ProgressStatus extends StatelessWidget {
  const ProgressStatus({super.key, required this.label, this.value, this.spokenLabel});

  final String label;
  final double? value;
  final String? spokenLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          label: spokenLabel ?? label,
          excludeSemantics: true,
          child: Text(label),
        ),
        const SizedBox(height: 6),
        // Le texte porte déjà l'information : la barre seule ne dit rien de plus au lecteur d'écran.
        ExcludeSemantics(child: LinearProgressIndicator(value: value)),
      ],
    );
  }
}
