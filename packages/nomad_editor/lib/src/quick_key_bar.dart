import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart' show CodeEditorTapRegion;

import 'nomad_editor_controller.dart';

/// Taille minimale d'une zone tactile (Material, WCAG 2.5.8 et RGAA).
const double kQuickKeyMinSize = 48;

/// Touche de la barre d'actions rapides.
class QuickKey {
  const QuickKey({this.label, this.icon, required this.tooltip, this.semanticLabel, required this.onPressed})
      : assert(label != null || icon != null);

  final String? label;
  final IconData? icon;
  final String tooltip;

  /// Texte lu par le lecteur d'écran, quand il diffère du libellé visible (« deux-points » pour « : »).
  /// Par défaut : [tooltip].
  final String? semanticLabel;

  /// Null : touche désactivée.
  final VoidCallback? onPressed;
}

/// Rangée de touches à placer au-dessus du clavier virtuel. Elle défile
/// horizontalement quand l'écran est trop étroit.
class QuickKeyBar extends StatelessWidget {
  const QuickKeyBar({super.key, required this.keys, this.semanticLabel});

  final List<QuickKey> keys;

  /// Nom de la barre pour le lecteur d'écran.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // re_editor retire le focus (donc ferme le clavier virtuel) à tout toucher hors de
    // lui : la barre doit compter comme une partie de l'éditeur, et du groupe des champs
    // de texte pour la saisie de code de la console.
    return TextFieldTapRegion(
      child: CodeEditorTapRegion(
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: semanticLabel,
          child: Material(
            color: scheme.surfaceContainerHigh,
            child: SizedBox(
              height: kQuickKeyMinSize + 8,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                itemCount: keys.length,
                separatorBuilder: (_, __) => const SizedBox(width: 4),
                itemBuilder: (context, i) => _QuickKeyButton(quickKey: keys[i]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickKeyButton extends StatelessWidget {
  const _QuickKeyButton({required this.quickKey});

  final QuickKey quickKey;

  @override
  Widget build(BuildContext context) {
    final key = quickKey;
    // Le libellé vocal remplace celui du bouton (« : » seul se lit mal) ; l'action reste portée
    // par la sémantique pour TalkBack et VoiceOver.
    return Semantics(
      button: true,
      enabled: key.onPressed != null,
      label: key.semanticLabel ?? key.tooltip,
      onTap: key.onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: key.tooltip,
        child: OutlinedButton(
          onPressed: key.onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(kQuickKeyMinSize, kQuickKeyMinSize),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            tapTargetSize: MaterialTapTargetSize.padded,
            textStyle: const TextStyle(fontFamily: 'Consolas', fontFamilyFallback: ['monospace'], fontSize: 16),
          ),
          child: key.icon != null ? Icon(key.icon, size: 22) : Text(key.label!),
        ),
      ),
    );
  }
}

/// Textes de la barre de symboles. Le paquet n'a pas de traductions : l'application fournit les siennes.
class SymbolBarLabels {
  const SymbolBarLabels({
    this.bar = 'Raccourcis de saisie',
    this.indent = 'Indenter',
    this.undo = 'Annuler',
    this.redo = 'Rétablir',
    this.insert = _defaultInsert,
    this.symbolNames = const {},
  });

  /// Nom de la barre.
  final String bar;
  final String indent;
  final String undo;
  final String redo;

  /// Libellé de l'insertion d'un symbole, à partir de son nom parlé.
  final String Function(String symbolName) insert;

  /// Nom parlé de chaque symbole (« : » → « deux-points »). Un symbole absent est lu tel quel.
  final Map<String, String> symbolNames;

  static String _defaultInsert(String name) => 'Insérer $name';
}

/// Barre de symboles de code pour clavier tactile, liée à un éditeur.
class SymbolBar extends StatelessWidget {
  const SymbolBar({super.key, required this.controller, this.labels = const SymbolBarLabels()});

  final NomadEditorController controller;
  final SymbolBarLabels labels;

  /// Touches les plus utiles d'abord : visibles sans défiler sur un téléphone.
  static const primarySymbols = [':', '{', '}'];

  /// Autres symboles courants en Python et en C.
  static const secondarySymbols = ['(', ')', '[', ']', '"', "'", '_', '=', '#', ',', '.', ';', '<', '>', '/', r'\'];

  List<QuickKey> get keys {
    QuickKey symbol(String s) {
      final text = labels.insert(labels.symbolNames[s] ?? s);
      return QuickKey(label: s, tooltip: text, onPressed: () => controller.insert(s));
    }

    return [
      QuickKey(label: 'Tab', tooltip: labels.indent, onPressed: controller.indent),
      for (final s in primarySymbols) symbol(s),
      QuickKey(icon: Icons.undo, tooltip: labels.undo, onPressed: controller.undo),
      QuickKey(icon: Icons.redo, tooltip: labels.redo, onPressed: controller.redo),
      for (final s in secondarySymbols) symbol(s),
    ];
  }

  @override
  Widget build(BuildContext context) => QuickKeyBar(keys: keys, semanticLabel: labels.bar);
}
