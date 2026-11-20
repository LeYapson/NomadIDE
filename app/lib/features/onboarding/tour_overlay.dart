import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/brand.dart';
import '../../l10n/l10n.dart';
import 'tour.dart';

/// Voile sombre posé sur les vrais écrans, avec un trou sur l'élément de l'étape et une carte qui l'explique.
/// Sans élément (ou s'il n'est pas à l'écran, clavier ouvert par exemple), la carte est au centre.
class TourOverlay extends ConsumerStatefulWidget {
  const TourOverlay({super.key});

  @override
  ConsumerState<TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends ConsumerState<TourOverlay> with WidgetsBindingObserver {
  static const _scrim = Color(0xB3000000);
  static const _pad = 6.0;
  static const _gap = 12.0;

  Rect? _hole;
  int? _holeFor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _measureLater();

  void _measureLater() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _measure();
      });

  /// Cherche l'élément de l'étape à l'écran, une fois la mise en page faite. `setState` seulement si le
  /// résultat change, donc pas de boucle.
  void _measure() {
    final index = ref.read(tourProvider);
    if (index == null) return;
    Rect? rect;
    final target = tourSteps[index].target;
    if (target != null) {
      final box = ref.read(tourTargetsProvider).keyOf(target).currentContext?.findRenderObject();
      final here = context.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize && !box.size.isEmpty && here is RenderBox && here.hasSize) {
        rect = here.globalToLocal(box.localToGlobal(Offset.zero)) & box.size;
      }
    }
    if (rect != _hole || index != _holeFor) {
      setState(() {
        _hole = rect;
        _holeFor = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(tourProvider);
    if (index == null) return const SizedBox.shrink();
    _measureLater();
    final step = tourSteps[index];
    final controller = ref.read(tourProvider.notifier);

    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.biggest;
      final measured = _holeFor == index ? _hole : null;
      final hole = measured?.inflate(_pad).intersect(Offset.zero & size);
      final visible = hole != null && !hole.isEmpty ? hole : null;

      return Stack(
        children: [
          ExcludeSemantics(child: _Scrim(color: _scrim, size: size, hole: visible)),
          if (visible != null) ...[
            Positioned.fromRect(
              key: const ValueKey('tour-hole'),
              rect: visible,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            // Élément non utilisable pendant la visite : le toucher passe à l'étape suivante.
            if (!step.interactive)
              Positioned.fromRect(
                rect: visible,
                child: ExcludeSemantics(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: controller.next)),
              ),
          ],
          _positioned(
            size: size,
            hole: visible,
            child: _TourCard(index: index, step: step, hole: visible != null, controller: controller),
          ),
        ],
      );
    });
  }

  /// La carte va du côté de l'écran où il y a de la place : sous l'élément s'il est en haut, au-dessus sinon.
  Widget _positioned({required Size size, required Rect? hole, required Widget child}) {
    const margin = 16.0;
    final above = hole != null && hole.center.dy > size.height / 2;
    final room = hole == null
        ? size.height - 2 * margin
        : above
            ? hole.top - _gap - margin
            : size.height - hole.bottom - _gap - margin;
    final card = ConstrainedBox(constraints: BoxConstraints(maxWidth: 480, maxHeight: math.max(room, 160)), child: child);
    if (hole == null) return Positioned.fill(child: Center(child: Padding(padding: const EdgeInsets.all(margin), child: card)));
    return Positioned(
      left: margin,
      right: margin,
      top: above ? null : hole.bottom + _gap,
      bottom: above ? size.height - hole.top + _gap : null,
      child: Align(heightFactor: 1, child: card),
    );
  }
}

/// Voile qui laisse un trou : quatre rectangles autour de [hole], qui absorbent les touchers. Le trou, lui, laisse
/// passer les touchers (l'élément éclairé reste utilisable).
class _Scrim extends StatelessWidget {
  const _Scrim({required this.color, required this.size, required this.hole});

  final Color color;
  final Size size;
  final Rect? hole;

  Widget get _absorbing => GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {}, child: ColoredBox(color: color));

  Widget _block(Rect rect) => Positioned.fromRect(rect: rect, child: _absorbing);

  @override
  Widget build(BuildContext context) {
    final h = hole;
    // Pas d'élément : tout l'écran est voilé.
    if (h == null) return SizedBox.fromSize(size: size, child: _absorbing);
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        children: [
          _block(Rect.fromLTRB(0, 0, size.width, h.top)),
          _block(Rect.fromLTRB(0, h.bottom, size.width, size.height)),
          _block(Rect.fromLTRB(0, h.top, h.left, h.bottom)),
          _block(Rect.fromLTRB(h.right, h.top, size.width, h.bottom)),
        ],
      ),
    );
  }
}

/// La carte : position dans la visite (annoncée), titre, texte, consigne, boutons.
class _TourCard extends StatelessWidget {
  const _TourCard({required this.index, required this.step, required this.hole, required this.controller});

  final int index;
  final TourStep step;
  final bool hole;
  final TourController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final last = index == tourSteps.length - 1;
    final welcome = index == 0;

    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: Material(
        elevation: 8,
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        // Le texte défile si l'écran est petit ou le texte agrandi ; les boutons, eux, restent toujours visibles.
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        liveRegion: true,
                        child: Text(l10n.obProgress(index + 1, tourSteps.length), style: theme.textTheme.labelLarge),
                      ),
                      const SizedBox(height: 8),
                      if (welcome) ...[
                        const Center(child: NomadLogo(size: 64)),
                        const SizedBox(height: 8),
                      ],
                      Semantics(header: true, child: Text(step.title(l10n), style: theme.textTheme.titleLarge)),
                      const SizedBox(height: 8),
                      Text(step.body(l10n), style: theme.textTheme.bodyMedium),
                      if (hole) ...[
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ExcludeSemantics(child: Icon(Icons.touch_app_outlined, size: 20, color: theme.colorScheme.primary)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                step.interactive ? l10n.tourTryHint : l10n.tourTapHint,
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!last) TextButton(onPressed: controller.finish, child: Text(l10n.obSkip)),
                  if (index > 0) OutlinedButton(onPressed: controller.back, child: Text(l10n.obBack)),
                  FilledButton(onPressed: controller.next, child: Text(last ? l10n.tourFinish : l10n.obNext)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
