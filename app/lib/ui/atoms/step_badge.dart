import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Pastille d'une étape : son numéro, ou une coche quand l'étape est terminée. Décorative : le nom de
/// l'étape et son état sont lus par [StepCard].
class StepBadge extends StatelessWidget {
  const StepBadge({super.key, required this.number, required this.done});

  final int number;
  final bool done;

  static const double size = 32;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.nomadColors;
    final background = done ? colors.success : scheme.primary;
    final foreground = done ? colors.onSuccess : scheme.onPrimary;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: done
            ? Icon(Icons.check, size: 20, color: foreground)
            : Text('$number', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: foreground)),
      ),
    );
  }
}
