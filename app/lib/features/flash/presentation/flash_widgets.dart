import 'package:flutter/material.dart';

/// Une étape numérotée de l'écran de flash : titre puis contenu.
class FlashStep extends StatelessWidget {
  const FlashStep({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

/// Résultat d'un flash : vert en cas de succès, rouge sinon.
class FlashBanner extends StatelessWidget {
  const FlashBanner({super.key, required this.message, required this.success});

  final String message;
  final bool success;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = success ? scheme.primaryContainer : scheme.errorContainer;
    final foreground = success ? scheme.onPrimaryContainer : scheme.onErrorContainer;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(success ? Icons.check_circle : Icons.error_outline, color: foreground),
          const SizedBox(width: 12),
          Expanded(child: SelectableText(message, style: TextStyle(color: foreground))),
        ],
      ),
    );
  }
}
