import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';

enum ProjectKind { micropython, arduino }

/// Ce que l'utilisateur a demandé dans la fenêtre « Nouveau projet ».
class NewProjectRequest {
  const NewProjectRequest({required this.name, required this.kind});

  final String name;
  final ProjectKind kind;
}

/// Demande le nom et le type du projet : MicroPython (vide) ou Arduino C/C++ (croquis de départ, compilé dans le cloud).
Future<NewProjectRequest?> showNewProjectDialog(BuildContext context) => showDialog<NewProjectRequest>(
      context: context,
      builder: (context) => const _NewProjectDialog(),
    );

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog();

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  TextEditingController? _name;
  ProjectKind _kind = ProjectKind.micropython;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _name ??= TextEditingController(text: context.l10n.prDefaultProjectName)
      ..selection = TextSelection(baseOffset: 0, extentOffset: context.l10n.prDefaultProjectName.length);
  }

  @override
  void dispose() {
    _name?.dispose();
    super.dispose();
  }

  void _confirm() {
    final name = _name!.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, NewProjectRequest(name: name, kind: _kind));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.prNewProject),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.prProjectNameLabel),
              onSubmitted: (_) => _confirm(),
            ),
            const SizedBox(height: 16),
            Semantics(header: true, child: Text(l10n.prKindLabel, style: Theme.of(context).textTheme.titleSmall)),
            RadioGroup<ProjectKind>(
              groupValue: _kind,
              onChanged: (kind) => setState(() => _kind = kind ?? _kind),
              child: Column(
                children: [
                  RadioListTile<ProjectKind>(
                    contentPadding: EdgeInsets.zero,
                    value: ProjectKind.micropython,
                    title: Text(l10n.prKindMicroPython),
                    subtitle: Text(l10n.prKindMicroPythonHint),
                  ),
                  RadioListTile<ProjectKind>(
                    contentPadding: EdgeInsets.zero,
                    value: ProjectKind.arduino,
                    title: Text(l10n.prKindArduino),
                    subtitle: Text(l10n.prKindArduinoHint),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.commonCancel)),
        FilledButton(onPressed: _confirm, child: Text(l10n.commonCreate)),
      ],
    );
  }
}
