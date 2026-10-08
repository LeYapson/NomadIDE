import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../l10n/l10n.dart';
import '../../application/serial_monitor_controller.dart';
import '../../domain/log_entry.dart';

/// Journal du flux série.
///
/// Défilement automatique vers le bas tant que l'utilisateur est en bas de la
/// liste. S'il remonte pour lire, on ne bouge plus.
class SerialLogView extends ConsumerStatefulWidget {
  const SerialLogView({super.key});

  @override
  ConsumerState<SerialLogView> createState() => _SerialLogViewState();
}

class _SerialLogViewState extends ConsumerState<SerialLogView> {
  final ScrollController _scroll = ScrollController();
  bool _followTail = true;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification || notification is UserScrollNotification) {
      final metrics = notification.metrics;
      _followTail = metrics.pixels >= metrics.maxScrollExtent - 24;
    }
    return false;
  }

  void _scrollToBottom([int attempts = 3]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_followTail || !_scroll.hasClients) return;
      final position = _scroll.position;
      if (position.pixels < position.maxScrollExtent) {
        _scroll.jumpTo(position.maxScrollExtent);
        // L'étendue d'une ListView paresseuse n'est qu'estimée : on recommence
        // jusqu'à atteindre la vraie fin.
        if (attempts > 1) _scrollToBottom(attempts - 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(serialMonitorProvider.select((s) => s.entries));
    final partial = ref.watch(serialMonitorProvider.select((s) => s.partialLine));
    final hexView = ref.watch(serialMonitorProvider.select((s) => s.hexView));
    final showTimestamps = ref.watch(serialMonitorProvider.select((s) => s.showTimestamps));
    final scheme = Theme.of(context).colorScheme;

    final count = entries.length + (partial == null ? 0 : 1);
    if (_followTail) _scrollToBottom();

    return ColoredBox(
      color: scheme.surfaceContainerLowest,
      child: count == 0
          ? Center(
              child: Text(
                context.l10n.monEmptyLog,
                style: TextStyle(color: scheme.outline),
              ),
            )
          : NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: count,
                itemBuilder: (context, index) {
                  final isPartial = index == entries.length;
                  final entry = isPartial ? LogEntry(kind: LogKind.rx, bytes: partial!) : entries[index];
                  return _LogLine(
                    entry: entry,
                    hexView: hexView,
                    showTimestamp: showTimestamps && !isPartial,
                  );
                },
              ),
            ),
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry, required this.hexView, required this.showTimestamp});

  final LogEntry entry;
  final bool hexView;
  final bool showTimestamp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (prefix, color) = switch (entry.kind) {
      LogKind.rx => ('', scheme.onSurface),
      LogKind.tx => ('→ ', scheme.primary),
      LogKind.system => ('• ', scheme.tertiary),
      LogKind.error => ('✖ ', scheme.error),
    };
    final isData = entry.kind == LogKind.rx || entry.kind == LogKind.tx;
    final body = hexView && isData ? entry.hex : entry.text;

    return Text.rich(
      TextSpan(children: [
        if (showTimestamp) TextSpan(text: '${_formatTime(entry.time)}  ', style: TextStyle(color: scheme.outline)),
        TextSpan(text: '$prefix$body', style: TextStyle(color: color)),
      ]),
      style: monoTextStyle,
    );
  }

  static String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.${t.millisecond.toString().padLeft(3, '0')}';
  }
}
