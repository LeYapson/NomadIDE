import 'package:flutter/painting.dart';

/// Couleurs de coloration syntaxique de NomadMCU.
///
/// Les fonds suivent la palette de la marque (Obsidian Dark, Soft Chalk). Chaque teinte de texte
/// respecte un contraste d'au moins 4,5:1 sur son fond (WCAG AA) ; le test
/// `syntax_theme_test.dart` le vérifie pour chaque entrée.
const Color nomadDarkBackground = Color(0xFF111318);
const Color nomadDarkForeground = Color(0xFFF3F4F6);
const Color nomadLightBackground = Color(0xFFF8F9FB);
const Color nomadLightForeground = Color(0xFF111318);

Map<String, TextStyle> _syntax({
  required Color background,
  required Color text,
  required Color comment,
  required Color keyword,
  required Color string,
  required Color number,
  required Color type,
  required Color title,
  required Color meta,
  required Color deletion,
}) {
  TextStyle c(Color color, {FontStyle? style, FontWeight? weight}) =>
      TextStyle(color: color, fontStyle: style, fontWeight: weight);
  return {
    'root': TextStyle(color: text, backgroundColor: background),
    'comment': c(comment, style: FontStyle.italic),
    'quote': c(comment, style: FontStyle.italic),
    'doctag': c(keyword),
    'keyword': c(keyword),
    'formula': c(keyword),
    'section': c(title),
    'name': c(deletion),
    'selector-tag': c(deletion),
    'deletion': c(deletion),
    'subst': c(text),
    'literal': c(number),
    'string': c(string),
    'regexp': c(string),
    'addition': c(string),
    'attribute': c(number),
    'meta-string': c(string),
    'built_in': c(type),
    'class': c(type),
    'title': c(title),
    'selector-id': c(title),
    'selector-class': c(number),
    'variable': c(text),
    'template-variable': c(deletion),
    'type': c(type),
    'symbol': c(title),
    'bullet': c(title),
    'link': c(title),
    'meta': c(meta),
    'selector-attr': c(title),
    'selector-pseudo': c(title),
    'number': c(number),
    'emphasis': const TextStyle(fontStyle: FontStyle.italic),
    'strong': const TextStyle(fontWeight: FontWeight.bold),
  };
}

/// Thème sombre : fond Obsidian Dark, texte Soft Chalk, mots-clés en indigo clair.
final Map<String, TextStyle> nomadDarkSyntax = _syntax(
  background: nomadDarkBackground,
  text: nomadDarkForeground,
  comment: const Color(0xFF9AA3B5),
  keyword: const Color(0xFFA5B4FC),
  string: const Color(0xFF6EE7B7),
  number: const Color(0xFFFDBA74),
  type: const Color(0xFF67E8F9),
  title: const Color(0xFF93C5FD),
  meta: const Color(0xFFFCD34D),
  deletion: const Color(0xFFFCA5A5),
);

/// Thème clair : mêmes rôles, teintes plus sombres pour rester lisibles sur fond clair.
final Map<String, TextStyle> nomadLightSyntax = _syntax(
  background: nomadLightBackground,
  text: nomadLightForeground,
  comment: const Color(0xFF576074),
  keyword: const Color(0xFF4338CA),
  string: const Color(0xFF047857),
  number: const Color(0xFF9A3412),
  type: const Color(0xFF0E7490),
  title: const Color(0xFF1D4ED8),
  meta: const Color(0xFF854D0E),
  deletion: const Color(0xFFB91C1C),
);
