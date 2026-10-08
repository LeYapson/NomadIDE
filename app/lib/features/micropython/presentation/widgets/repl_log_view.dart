import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/micropython_controller.dart';

/// Journal de la carte (commandes, sortie, erreurs), défilant avec les nouveaux messages.
class ReplLogView extends ConsumerStatefulWidget {
  const ReplLogView({super.key});

  @override
  ConsumerState<ReplLogView> createState() => _ReplLogViewState();
}

class _ReplLogViewState extends ConsumerState<ReplLogView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final log = ref.watch(microPythonProvider.select((s) => s.log));
    final scheme = Theme.of(context).colorScheme;

    ref.listen(microPythonProvider.select((s) => s.log), (_, __) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    });

    Color colorOf(ReplLogKind kind) => switch (kind) {
          ReplLogKind.info => scheme.outline,
          ReplLogKind.input => scheme.primary,
          ReplLogKind.out => scheme.onSurface,
          ReplLogKind.err => scheme.error,
        };

    return SelectionArea(
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(8),
        itemCount: log.length,
        itemBuilder: (context, i) {
          final e = log[i];
          final prefix = switch (e.kind) {
            ReplLogKind.info => '· ',
            ReplLogKind.input => '>>> ',
            _ => '',
          };
          return Text(
            '$prefix${e.text}',
            style: TextStyle(fontFamily: 'Consolas', fontFamilyFallback: const ['monospace'], color: colorOf(e.kind)),
          );
        },
      ),
    );
  }
}
