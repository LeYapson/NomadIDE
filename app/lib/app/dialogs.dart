import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// Demande une ligne de texte. Renvoie null si l'utilisateur annule ou ne saisit rien.
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  required String label,
  String initialValue = '',
  String? confirmLabel,
  String? cancelLabel,
  String? helper,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _TextInputDialog(
      title: title,
      label: label,
      initialValue: initialValue,
      confirmLabel: confirmLabel ?? context.l10n.commonOk,
      cancelLabel: cancelLabel ?? context.l10n.commonCancel,
      helper: helper,
    ),
  );
}

/// Le contrôleur appartient au dialogue : le libérer à la fermeture de la route,
/// avant la fin de l'animation de sortie, ferait planter le champ encore affiché.
class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.helper,
  });

  final String title;
  final String label;
  final String initialValue;
  final String confirmLabel;
  final String cancelLabel;
  final String? helper;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _field = TextEditingController(text: widget.initialValue);

  @override
  void initState() {
    super.initState();
    // Sélectionne le nom sans l'extension pour permettre de le remplacer d'une frappe.
    final dot = widget.initialValue.lastIndexOf('.');
    _field.selection = TextSelection(baseOffset: 0, extentOffset: dot > 0 ? dot : widget.initialValue.length);
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _confirm() {
    final value = _field.text.trim();
    Navigator.pop(context, value.isEmpty ? null : value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _field,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label, helperText: widget.helper),
        onSubmitted: (_) => _confirm(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.cancelLabel)),
        FilledButton(onPressed: _confirm, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

/// Demande une confirmation. [destructive] colore le bouton en rouge.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(cancelLabel ?? context.l10n.commonCancel)),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel ?? context.l10n.commonOk),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
