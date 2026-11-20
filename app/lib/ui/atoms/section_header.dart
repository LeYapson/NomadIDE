import 'package:flutter/material.dart';

/// Titre d'une section d'écran (Réglages, bibliothèques…) : couleur de marque, déclaré comme titre au lecteur
/// d'écran, qui peut ainsi sauter de section en section.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.padding = const EdgeInsets.fromLTRB(16, 20, 16, 4)});

  final String text;

  /// Marge autour du titre : celle d'une liste pleine largeur par défaut.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Semantics(
        header: true,
        child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
      ),
    );
  }
}
