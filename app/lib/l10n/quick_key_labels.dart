import 'package:nomad_editor/nomad_editor.dart';

import 'l10n.dart';

/// Nom parlé d'un symbole, pour le lecteur d'écran (« : » se lit « deux-points »).
Map<String, String> symbolNames(AppLocalizations l10n) => {
      ':': l10n.qkSymColon,
      '{': l10n.qkSymBraceOpen,
      '}': l10n.qkSymBraceClose,
      '(': l10n.qkSymParenOpen,
      ')': l10n.qkSymParenClose,
      '[': l10n.qkSymBracketOpen,
      ']': l10n.qkSymBracketClose,
      '"': l10n.qkSymDoubleQuote,
      "'": l10n.qkSymSingleQuote,
      '_': l10n.qkSymUnderscore,
      '=': l10n.qkSymEquals,
      '#': l10n.qkSymHash,
      ',': l10n.qkSymComma,
      '.': l10n.qkSymDot,
      ';': l10n.qkSymSemicolon,
      '<': l10n.qkSymLess,
      '>': l10n.qkSymGreater,
      '/': l10n.qkSymSlash,
      r'\': l10n.qkSymBackslash,
    };

/// Libellés traduits de la barre de symboles de l'éditeur.
SymbolBarLabels symbolBarLabels(AppLocalizations l10n) => SymbolBarLabels(
      bar: l10n.qkBarLabel,
      indent: l10n.qkTabTooltip,
      undo: l10n.qkUndo,
      redo: l10n.qkRedo,
      insert: l10n.qkInsert,
      symbolNames: symbolNames(l10n),
    );
