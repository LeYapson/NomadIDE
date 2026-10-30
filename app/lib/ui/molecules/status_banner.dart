import 'package:flutter/material.dart';

import '../../app/theme.dart';

enum StatusKind { success, error, info }

/// Résultat d'une opération : une icône, un texte, et une couleur. La couleur n'est jamais seule à porter
/// le sens (icône et texte la doublent). Annoncé au lecteur d'écran dès qu'il apparaît.
class StatusBanner extends StatelessWidget {
  const StatusBanner({super.key, required this.message, required this.kind});

  final String message;
  final StatusKind kind;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.nomadColors;
    final (background, foreground, icon) = switch (kind) {
      StatusKind.success => (colors.successContainer, colors.onSuccessContainer, Icons.check_circle),
      StatusKind.error => (scheme.errorContainer, scheme.onErrorContainer, Icons.error_outline),
      StatusKind.info => (scheme.secondaryContainer, scheme.onSecondaryContainer, Icons.info_outline),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Icon(icon, color: foreground)),
            const SizedBox(width: 12),
            Expanded(child: SelectableText(message, style: TextStyle(color: foreground))),
          ],
        ),
      ),
    );
  }
}
