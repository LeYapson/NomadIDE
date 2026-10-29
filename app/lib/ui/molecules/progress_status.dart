import 'package:flutter/material.dart';

/// Texte d'une phase en cours et barre de progression. [value] nul : durée inconnue (barre sans fin).
class ProgressStatus extends StatelessWidget {
  const ProgressStatus({super.key, required this.label, this.value});

  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 6),
        // Le pourcentage est déjà dans le texte : la barre seule ne dit rien de plus au lecteur d'écran.
        ExcludeSemantics(child: LinearProgressIndicator(value: value)),
      ],
    );
  }
}
