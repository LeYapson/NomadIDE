import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_compile_api/nomad_compile_api.dart';

import '../../../l10n/l10n.dart';
import '../application/arduino_libraries_controller.dart';
import 'compile_messages.dart';

/// Feuille des bibliothèques Arduino d'un projet : ce qu'il utilise, les `#include` sans bibliothèque, la recherche.
Future<void> showArduinoLibrariesSheet(BuildContext context, {required String project, required CompileBoard board}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (_) => ArduinoLibrariesSheet(project: project, board: board),
    );

class ArduinoLibrariesSheet extends ConsumerStatefulWidget {
  const ArduinoLibrariesSheet({super.key, required this.project, required this.board});

  final String project;
  final CompileBoard board;

  @override
  ConsumerState<ArduinoLibrariesSheet> createState() => _ArduinoLibrariesSheetState();
}

class _ArduinoLibrariesSheetState extends ConsumerState<ArduinoLibrariesSheet> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(arduinoLibrariesProvider.notifier).load(widget.project, widget.board));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQuery(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => ref.read(arduinoLibrariesProvider.notifier).search(text));
  }

  Future<void> _scan() async {
    await ref.read(arduinoLibrariesProvider.notifier).scan();
    if (mounted) setState(() => _scanned = true);
  }

  Future<void> _openDetail(String name, {String? currentVersion}) async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (_) => _LibraryDialog(name: name, currentVersion: currentVersion),
    );
    if (chosen == null) return;
    final controller = ref.read(arduinoLibrariesProvider.notifier);
    if (currentVersion == null) {
      await controller.add(name, version: chosen);
    } else {
      await controller.setVersion(name, chosen);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final state = ref.watch(arduinoLibrariesProvider);
    final controller = ref.read(arduinoLibrariesProvider.notifier);

    final children = <Widget>[
      Semantics(header: true, child: Text(l10n.alTitle, style: theme.textTheme.titleLarge)),
      const SizedBox(height: 8),
      if (state.problem != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Semantics(
            liveRegion: true,
            child: Text(compileProblemMessage(l10n, state.problem!, state.detail), style: TextStyle(color: theme.colorScheme.error)),
          ),
        ),
      if (state.working) const LinearProgressIndicator(),

      // --- Dans ce projet
      _SectionTitle(l10n.alProjectSection),
      if (state.chosen.isEmpty)
        Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(l10n.alNoneYet))
      else
        for (final library in state.chosen)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(library.name),
            subtitle: Text(l10n.alVersion(library.version)),
            onTap: () => _openDetail(library.name, currentVersion: library.version),
            trailing: IconButton(
              tooltip: l10n.alRemove(library.name),
              onPressed: state.working ? null : () => controller.remove(library.name),
              icon: const Icon(Icons.delete_outline),
            ),
          ),
      if (state.dependencies.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.alDependencies(state.dependencies.map((d) => '${d.name} ${d.version}').join(', ')),
            style: theme.textTheme.bodySmall,
          ),
        ),

      // --- #include sans bibliothèque
      _SectionTitle(l10n.alSuggestionsTitle),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          onPressed: state.scanning ? null : _scan,
          icon: state.scanning
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.manage_search),
          label: Text(state.scanning ? l10n.alScanning : l10n.alScan),
        ),
      ),
      if (_scanned && !state.scanning && state.suggestions.isEmpty && state.problem == null)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(l10n.alAllProvided)),
      for (final resolution in state.suggestions) _Suggestion(resolution: resolution, working: state.working),

      // --- Recherche
      _SectionTitle(l10n.alSearchLabel),
      TextField(
        controller: _search,
        autocorrect: false,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          labelText: l10n.alSearchLabel,
          hintText: l10n.alSearchHint,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.search),
        ),
        onChanged: _onQuery,
        onSubmitted: (text) {
          _debounce?.cancel();
          controller.search(text);
        },
      ),
      const SizedBox(height: 8),
      if (state.searching) Semantics(liveRegion: true, child: Text(l10n.alSearching)),
      if (!state.searching && state.results != null) ..._results(context, state),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: ListView(shrinkWrap: true, children: children),
    );
  }

  List<Widget> _results(BuildContext context, ArduinoLibrariesState state) {
    final l10n = context.l10n;
    final results = state.results!;
    if (results.libraries.isEmpty) return [Text(l10n.alNoResults)];
    return [
      Semantics(
        liveRegion: true,
        child: Text(l10n.alResultsCount(results.libraries.length, results.total), style: Theme.of(context).textTheme.bodySmall),
      ),
      for (final library in results.libraries)
        _ResultTile(
          library: library,
          added: state.has(library.name),
          working: state.working,
          onOpen: () => _openDetail(library.name),
        ),
    ];
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Semantics(header: true, child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
      );
}

class _ResultTile extends ConsumerWidget {
  const _ResultTile({required this.library, required this.added, required this.working, required this.onOpen});

  final LibrarySummary library;
  final bool added;
  final bool working;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final license = library.license == null ? l10n.alLicenseUnknown : l10n.alLicense(library.license!);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('${library.name} ${library.latest}'),
      subtitle: Text('${library.sentence}\n${l10n.alAuthor(library.author)} · $license'),
      isThreeLine: true,
      onTap: onOpen,
      trailing: added
          ? Chip(label: Text(l10n.alAdded), avatar: const Icon(Icons.check, size: 18))
          : FilledButton.tonal(
              onPressed: working ? null : () => ref.read(arduinoLibrariesProvider.notifier).add(library.name),
              child: Semantics(label: l10n.alAddLibrary(library.name), excludeSemantics: true, child: Text(l10n.alAdd)),
            ),
    );
  }
}

/// Un `#include` sans bibliothèque, avec les bibliothèques qui peuvent le fournir.
class _Suggestion extends ConsumerWidget {
  const _Suggestion({required this.resolution, required this.working});

  final IncludeResolution resolution;
  final bool working;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.alSuggestionBody(resolution.header)),
            if (resolution.candidates.isEmpty)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(l10n.alSuggestionNone(resolution.header), style: theme.textTheme.bodySmall)),
            for (final candidate in resolution.candidates.take(3))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${candidate.name} ${candidate.latest}'),
                subtitle: Text(
                  '${l10n.alAuthor(candidate.author)} · ${resolution.confirmed.contains(candidate.name) ? l10n.alConfirmed : l10n.alGuess}',
                ),
                trailing: FilledButton.tonal(
                  onPressed: working ? null : () => ref.read(arduinoLibrariesProvider.notifier).add(candidate.name),
                  child: Semantics(label: l10n.alAddLibrary(candidate.name), excludeSemantics: true, child: Text(l10n.alAdd)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Détail d'une bibliothèque : description, licence, et choix de la version. Renvoie la version choisie.
class _LibraryDialog extends ConsumerStatefulWidget {
  const _LibraryDialog({required this.name, this.currentVersion});

  final String name;

  /// Version actuelle quand la bibliothèque est déjà dans le projet (le bouton change alors de version).
  final String? currentVersion;

  @override
  ConsumerState<_LibraryDialog> createState() => _LibraryDialogState();
}

class _LibraryDialogState extends ConsumerState<_LibraryDialog> {
  LibraryDetail? _detail;
  bool _failed = false;
  String? _version;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final detail = await ref.read(arduinoLibrariesProvider.notifier).detailOf(widget.name);
    if (!mounted) return;
    setState(() {
      _detail = detail;
      _failed = detail == null;
      _version = widget.currentVersion ?? detail?.versions.firstOrNull?.version;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final detail = _detail;
    final adding = widget.currentVersion == null;
    return AlertDialog(
      title: Text(widget.name),
      content: SingleChildScrollView(
        child: detail == null
            ? (_failed ? const SizedBox.shrink() : Semantics(liveRegion: true, child: Text(l10n.alLoadingVersions)))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(detail.summary.sentence),
                  if (detail.paragraph.isNotEmpty && detail.paragraph != detail.summary.sentence)
                    Padding(padding: const EdgeInsets.only(top: 8), child: Text(detail.paragraph)),
                  const SizedBox(height: 8),
                  Text('${l10n.alAuthor(detail.summary.author)} · '
                      '${detail.summary.license == null ? l10n.alLicenseUnknown : l10n.alLicense(detail.summary.license!)}'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _version,
                    decoration: InputDecoration(labelText: l10n.alVersionPick, border: const OutlineInputBorder()),
                    items: [
                      for (final v in detail.versions)
                        DropdownMenuItem(
                          value: v.version,
                          child: Text(v.version == detail.summary.latest ? l10n.alVersionLatest(v.version) : v.version),
                        ),
                    ],
                    onChanged: (v) => setState(() => _version = v),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
        FilledButton(
          onPressed: _version == null || (!adding && _version == widget.currentVersion) ? null : () => Navigator.pop(context, _version),
          child: Text(adding ? l10n.alAdd : l10n.alChangeVersion),
        ),
      ],
    );
  }
}
