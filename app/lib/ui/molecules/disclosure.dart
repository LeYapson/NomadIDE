import 'package:flutter/material.dart';

/// Section secondaire repliée par défaut (options avancées, source de téléchargement). L'en-tête mesure
/// au moins 48 dp ; [summary] rappelle l'essentiel quand la section est fermée.
class Disclosure extends StatefulWidget {
  const Disclosure({
    super.key,
    required this.title,
    required this.children,
    this.summary,
    this.initiallyExpanded = false,
  });

  final String title;
  final String? summary;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  State<Disclosure> createState() => _DisclosureState();
}

class _DisclosureState extends State<Disclosure> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            label: widget.title,
            value: _expanded ? null : widget.summary,
            onTap: _toggle,
            excludeSemantics: true,
            child: InkWell(
              onTap: _toggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.title, style: Theme.of(context).textTheme.titleSmall),
                            if (!_expanded && widget.summary != null)
                              Text(widget.summary!, style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                      Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: scheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: widget.children),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
