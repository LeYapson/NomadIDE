import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Bouton d'une action qui touche la carte physique (Flasher, Exécuter) : Solar Amber, texte sombre,
/// zone tactile d'au moins 48 dp.
class HardwareButton extends StatelessWidget {
  const HardwareButton({super.key, required this.onPressed, required this.icon, required this.label});

  /// Null : bouton désactivé.
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: hardwareButtonStyle(context),
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
