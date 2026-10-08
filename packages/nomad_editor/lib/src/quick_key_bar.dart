import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart' show CodeEditorTapRegion;

import 'nomad_editor_controller.dart';

/// Touche de la barre d'actions rapides.
class QuickKey {
  const QuickKey({this.label, this.icon, required this.tooltip, required this.onPressed})
      : assert(label != null || icon != null);

  final String? label;
  final IconData? icon;
  final String tooltip;

  /// Null : touche désactivée.
  final VoidCallback? onPressed;
}

/// Rangée de touches à placer au-dessus du clavier virtuel. Elle défile
/// horizontalement quand l'écran est trop étroit.
class QuickKeyBar extends StatelessWidget {
  const QuickKeyBar({super.key, required this.keys});

  final List<QuickKey> keys;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // re_editor retire le focus (donc ferme le clavier virtuel) à tout toucher hors de
    // lui : la barre doit compter comme une partie de l'éditeur, et du groupe des champs
    // de texte pour la saisie de code de la console.
    return TextFieldTapRegion(
      child: CodeEditorTapRegion(
        child: Material(
          color: scheme.surfaceContainerHigh,
          child: SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              itemCount: keys.length,
              separatorBuilder: (_, __) => const SizedBox(width: 4),
              itemBuilder: (context, i) {
                final key = keys[i];
                return Tooltip(
                  message: key.tooltip,
                  child: OutlinedButton(
                    onPressed: key.onPressed,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(44, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      textStyle: const TextStyle(fontFamily: 'Consolas', fontFamilyFallback: ['monospace'], fontSize: 16),
                    ),
                    child: key.icon != null ? Icon(key.icon, size: 20) : Text(key.label!),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Barre de symboles de code pour clavier tactile, liée à un éditeur.
class SymbolBar extends StatelessWidget {
  const SymbolBar({super.key, required this.controller});

  final NomadEditorController controller;

  /// Touches les plus utiles d'abord : visibles sans défiler sur un téléphone.
  static const primarySymbols = [':', '{', '}'];

  /// Autres symboles courants en Python et en C.
  static const secondarySymbols = ['(', ')', '[', ']', '"', "'", '_', '=', '#', ',', '.', ';', '<', '>', '/', r'\'];

  List<QuickKey> get keys {
    QuickKey symbol(String s) =>
        QuickKey(label: s, tooltip: 'Insérer $s', onPressed: () => controller.insert(s));
    return [
      QuickKey(label: 'Tab', tooltip: 'Indenter', onPressed: controller.indent),
      for (final s in primarySymbols) symbol(s),
      QuickKey(icon: Icons.undo, tooltip: 'Annuler', onPressed: controller.undo),
      QuickKey(icon: Icons.redo, tooltip: 'Rétablir', onPressed: controller.redo),
      for (final s in secondarySymbols) symbol(s),
    ];
  }

  @override
  Widget build(BuildContext context) => QuickKeyBar(keys: keys);
}
