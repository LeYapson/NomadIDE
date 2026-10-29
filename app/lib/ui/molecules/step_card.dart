import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../atoms/step_badge.dart';

/// Une étape d'un parcours guidé (« 2 sur 3 : Carte »).
///
/// Divulgation progressive : tant que l'étape n'est pas [done], elle est ouverte ; une fois terminée, elle
/// se replie sur son [summary] (ce qui a été choisi) et se rouvre d'un toucher pour la modifier. Une étape
/// que l'utilisateur a ouverte ou fermée lui-même garde son choix jusqu'au prochain changement d'état.
class StepCard extends StatefulWidget {
  const StepCard({
    super.key,
    required this.number,
    required this.total,
    required this.title,
    required this.done,
    required this.children,
    this.summary,
    this.collapsible = true,
  });

  final int number;
  final int total;
  final String title;
  final bool done;

  /// Ce qui est affiché sous le titre quand l'étape est terminée et repliée.
  final Widget? summary;

  /// Faux pour l'étape finale (l'action et son résultat doivent rester visibles) : elle ne se replie jamais,
  /// mais [done] change toujours sa pastille.
  final bool collapsible;

  /// Le contenu de l'étape, construit seulement quand elle est ouverte.
  final List<Widget> children;

  @override
  State<StepCard> createState() => _StepCardState();
}

class _StepCardState extends State<StepCard> {
  /// Choix de l'utilisateur ; nul tant qu'il n'a pas touché l'en-tête.
  bool? _choice;

  bool get _expanded => _choice ?? !(widget.done && widget.collapsible);

  @override
  void didUpdateWidget(StepCard old) {
    super.didUpdateWidget(old);
    // Une étape qui vient d'être terminée (ou rouverte par l'application) reprend son comportement automatique.
    if (old.done != widget.done) _choice = null;
  }

  void _toggle() => setState(() => _choice = !_expanded);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final canToggle = widget.done && widget.collapsible;
    final expanded = _expanded;
    final label = '${l10n.stepA11y(widget.number, widget.total, widget.title)}, '
        '${widget.done ? l10n.stepDone : l10n.stepTodo}';

    final header = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            StepBadge(number: widget.number, done: widget.done),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium)),
                  if (!expanded && widget.summary != null) ...[const SizedBox(height: 2), widget.summary!],
                ],
              ),
            ),
            if (canToggle)
              ExcludeSemantics(child: Icon(expanded ? Icons.expand_less : Icons.expand_more, color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            container: true,
            button: canToggle,
            expanded: canToggle ? expanded : null,
            label: label,
            hint: canToggle ? (expanded ? l10n.stepHideDetails : l10n.stepShowDetails) : null,
            onTap: canToggle ? _toggle : null,
            excludeSemantics: true,
            child: canToggle ? InkWell(onTap: _toggle, child: header) : header,
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.topCenter,
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: widget.children),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
