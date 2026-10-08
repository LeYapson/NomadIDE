import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../application/projects_controller.dart';
import '../data/project_store.dart';

/// Emplacement choisi dans « Enregistrer sous ».
class SaveTarget {
  const SaveTarget({required this.project, required this.path, this.isNewProject = false});

  final String project;
  final String path;

  /// Le projet n'existe pas encore : l'appelant doit le créer avant d'écrire.
  final bool isNewProject;
}

/// Choix du projet et du chemin d'un fichier à enregistrer sur l'appareil.
Future<SaveTarget?> showSaveAsDialog(
  BuildContext context, {
  required List<String> projects,
  required String? currentProject,
  required String initialPath,
  String title = 'Enregistrer sur cet appareil',
  String confirmLabel = 'Enregistrer',
}) {
  return showDialog<SaveTarget>(
    context: context,
    builder: (context) => _SaveAsDialog(
      projects: projects,
      currentProject: currentProject,
      initialPath: initialPath,
      title: title,
      confirmLabel: confirmLabel,
    ),
  );
}

class _SaveAsDialog extends StatefulWidget {
  const _SaveAsDialog({
    required this.projects,
    required this.currentProject,
    required this.initialPath,
    required this.title,
    required this.confirmLabel,
  });

  final List<String> projects;
  final String? currentProject;
  final String initialPath;
  final String title;
  final String confirmLabel;

  @override
  State<_SaveAsDialog> createState() => _SaveAsDialogState();
}

class _SaveAsDialogState extends State<_SaveAsDialog> {
  static const _newProject = '\u0000nouveau';

  late String _selected =
      widget.projects.contains(widget.currentProject) ? widget.currentProject! : (widget.projects.firstOrNull ?? _newProject);
  late final TextEditingController _path = TextEditingController(text: widget.initialPath);
  final TextEditingController _newName = TextEditingController(text: 'Mon projet');

  @override
  void dispose() {
    _path.dispose();
    _newName.dispose();
    super.dispose();
  }

  void _confirm() {
    final path = _path.text.trim().replaceAll(RegExp(r'^/+'), '');
    final isNew = _selected == _newProject;
    final project = isNew ? _newName.text.trim() : _selected;
    if (path.isEmpty || project.isEmpty) return;
    Navigator.pop(context, SaveTarget(project: project, path: path, isNewProject: isNew));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selected,
            decoration: const InputDecoration(labelText: 'Projet'),
            items: [
              for (final name in widget.projects) DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis)),
              const DropdownMenuItem(value: _newProject, child: Text('Nouveau projet…')),
            ],
            onChanged: (value) => setState(() => _selected = value ?? _selected),
          ),
          if (_selected == _newProject) TextField(controller: _newName, decoration: const InputDecoration(labelText: 'Nom du nouveau projet')),
          const SizedBox(height: 8),
          TextField(
            controller: _path,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Fichier', helperText: 'Ex. main.py ou lib/capteur.py'),
            onSubmitted: (_) => _confirm(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: _confirm, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

/// Fichier choisi dans un projet.
class ProjectFile {
  const ProjectFile(this.project, this.path);

  final String project;
  final String path;
}

/// Parcourt les projets locaux pour choisir un fichier (ex. à envoyer sur la carte).
Future<ProjectFile?> showProjectFilePicker(BuildContext context) {
  return showDialog<ProjectFile>(context: context, builder: (context) => const _ProjectFilePicker());
}

class _ProjectFilePicker extends ConsumerStatefulWidget {
  const _ProjectFilePicker();

  @override
  ConsumerState<_ProjectFilePicker> createState() => _ProjectFilePickerState();
}

class _ProjectFilePickerState extends ConsumerState<_ProjectFilePicker> {
  late String? _project = ref.read(projectsProvider).current;
  String _directory = '';
  List<ProjectEntry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final project = _project;
    if (project == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final entries = await (await ref.read(projectStoreProvider.future)).listEntries(project, _directory);
      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _entries = const [];
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider).projects;
    return AlertDialog(
      title: const Text('Choisir un fichier à envoyer'),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: projects.contains(_project) ? _project : null,
              decoration: const InputDecoration(labelText: 'Projet'),
              hint: const Text('Aucun projet'),
              items: [for (final name in projects) DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis))],
              onChanged: (name) {
                setState(() {
                  _project = name;
                  _directory = '';
                  _loading = true;
                });
                _load();
              },
            ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Dossier parent',
                  onPressed: _directory.isEmpty
                      ? null
                      : () {
                          setState(() {
                            _directory = _directory.contains('/') ? _directory.substring(0, _directory.lastIndexOf('/')) : '';
                            _loading = true;
                          });
                          _load();
                        },
                  icon: const Icon(Icons.arrow_upward),
                ),
                Expanded(child: Text('/$_directory', overflow: TextOverflow.ellipsis)),
              ],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _entries.isEmpty
                      ? const Center(child: Text('Rien ici'))
                      : ListView(
                          children: [
                            for (final entry in _entries)
                              ListTile(
                                dense: true,
                                leading: Icon(entry.isDirectory ? Icons.folder_outlined : Icons.insert_drive_file_outlined),
                                title: Text(entry.name, overflow: TextOverflow.ellipsis),
                                onTap: () {
                                  if (entry.isDirectory) {
                                    setState(() {
                                      _directory = entry.path;
                                      _loading = true;
                                    });
                                    _load();
                                  } else {
                                    Navigator.pop(context, ProjectFile(_project!, entry.path));
                                  }
                                },
                              ),
                          ],
                        ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler'))],
    );
  }
}
