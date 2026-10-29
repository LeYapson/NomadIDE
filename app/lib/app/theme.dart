import 'package:flutter/material.dart';

// Palette NomadIDE. Les teintes marquées « ajusté » s'écartent légèrement de la charte pour tenir
// les contrastes WCAG 2.2 AA (voir PRD, épopée G) ; chaque couple texte/fond est vérifié par
// `test/theme_test.dart`.

/// Fond principal : Obsidian Dark (jamais du noir pur, plus reposant).
const Color obsidianDark = Color(0xFF111318);

/// Panneaux, terminal, barre de navigation : Deep Slate.
const Color deepSlate = Color(0xFF1B1E28);

/// Texte principal : Soft Chalk (16,9:1 sur Obsidian).
const Color softChalk = Color(0xFFF3F4F6);

/// Action matérielle : Solar Amber. Le texte posé dessus est sombre (6,6:1) ; le blanc (2,8:1) est interdit.
const Color solarAmber = Color(0xFFFF6B35);

/// Connexion et succès : Cyber Mint.
const Color cyberMint = Color(0xFF00E5A3);

/// Accent de marque : Electric Indigo, éclairci à `#818CF8` en thème sombre. Material colore le texte des
/// boutons et les libellés actifs avec cette teinte : `#6366F1` n'y atteint que 3,8:1 à 4,2:1, alors que
/// `#818CF8` fait 6,2:1 sur Obsidian et 5,6:1 sur Deep Slate (texte sombre posé dessus).
const Color electricIndigo = Color(0xFF818CF8);

/// Erreur et danger : Crimson Red, éclairci à `#F87171` en thème sombre (6,0:1 sur Deep Slate,
/// contre 4,4:1 pour `#EF4444`).
const Color crimsonRed = Color(0xFFF87171);

/// Couleurs propres à NomadIDE, hors du jeu de rôles Material.
@immutable
class NomadColors extends ThemeExtension<NomadColors> {
  const NomadColors({
    required this.hardware,
    required this.onHardware,
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
  });

  /// Boutons qui agissent sur la carte physique : Flasher, Exécuter, Redémarrer.
  final Color hardware;
  final Color onHardware;

  /// Carte connectée, flash réussi, REPL prêt.
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  static const dark = NomadColors(
    hardware: solarAmber,
    onHardware: obsidianDark,
    success: cyberMint,
    onSuccess: obsidianDark,
    successContainer: Color(0xFF0B3D30),
    onSuccessContainer: Color(0xFFA7F3D0),
  );

  static const light = NomadColors(
    hardware: solarAmber,
    onHardware: obsidianDark,
    success: Color(0xFF047857),
    onSuccess: Colors.white,
    successContainer: Color(0xFFD1FAE5),
    onSuccessContainer: Color(0xFF064E3B),
  );

  @override
  NomadColors copyWith({
    Color? hardware,
    Color? onHardware,
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
  }) =>
      NomadColors(
        hardware: hardware ?? this.hardware,
        onHardware: onHardware ?? this.onHardware,
        success: success ?? this.success,
        onSuccess: onSuccess ?? this.onSuccess,
        successContainer: successContainer ?? this.successContainer,
        onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      );

  @override
  NomadColors lerp(ThemeExtension<NomadColors>? other, double t) {
    if (other is! NomadColors) return this;
    return NomadColors(
      hardware: Color.lerp(hardware, other.hardware, t)!,
      onHardware: Color.lerp(onHardware, other.onHardware, t)!,
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer: Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
    );
  }
}

extension NomadThemeContext on BuildContext {
  NomadColors get nomadColors => Theme.of(this).extension<NomadColors>()!;
}

/// Style des boutons d'action sur la carte (Flasher, Exécuter, Redémarrer) : Solar Amber, texte sombre.
ButtonStyle hardwareButtonStyle(BuildContext context) {
  final colors = context.nomadColors;
  return FilledButton.styleFrom(backgroundColor: colors.hardware, foregroundColor: colors.onHardware);
}

const ColorScheme _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: electricIndigo,
  onPrimary: obsidianDark,
  primaryContainer: Color(0xFF2F3270),
  onPrimaryContainer: Color(0xFFE0E7FF),
  secondary: Color(0xFFA5B4FC),
  onSecondary: obsidianDark,
  secondaryContainer: Color(0xFF2F3270),
  onSecondaryContainer: softChalk,
  tertiary: Color(0xFF9CA3AF),
  onTertiary: obsidianDark,
  tertiaryContainer: Color(0xFF2A2E3C),
  onTertiaryContainer: softChalk,
  error: crimsonRed,
  onError: obsidianDark,
  errorContainer: Color(0xFF4A1818),
  onErrorContainer: Color(0xFFFECACA),
  surface: obsidianDark,
  onSurface: softChalk,
  onSurfaceVariant: Color(0xFFA7AEBB),
  outline: Color(0xFF7B8394),
  outlineVariant: Color(0xFF2E3342),
  shadow: Colors.black,
  scrim: Colors.black,
  inverseSurface: softChalk,
  onInverseSurface: obsidianDark,
  inversePrimary: Color(0xFF4338CA),
  surfaceTint: electricIndigo,
  surfaceDim: Color(0xFF0D0F14),
  surfaceBright: Color(0xFF2A2E3C),
  surfaceContainerLowest: Color(0xFF0D0F14),
  surfaceContainerLow: Color(0xFF161922),
  surfaceContainer: deepSlate,
  surfaceContainerHigh: Color(0xFF222633),
  surfaceContainerHighest: Color(0xFF2A2E3C),
);

const ColorScheme _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF4F46E5),
  onPrimary: Colors.white,
  primaryContainer: Color(0xFFE0E7FF),
  onPrimaryContainer: Color(0xFF1E1B4B),
  secondary: Color(0xFF4338CA),
  onSecondary: Colors.white,
  secondaryContainer: Color(0xFFE0E7FF),
  onSecondaryContainer: Color(0xFF1E1B4B),
  tertiary: Color(0xFF4B5563),
  onTertiary: Colors.white,
  tertiaryContainer: Color(0xFFE5E7EB),
  onTertiaryContainer: obsidianDark,
  error: Color(0xFFB91C1C),
  onError: Colors.white,
  errorContainer: Color(0xFFFEE2E2),
  onErrorContainer: Color(0xFF7F1D1D),
  surface: Color(0xFFF8F9FB),
  onSurface: obsidianDark,
  onSurfaceVariant: Color(0xFF4B5563),
  outline: Color(0xFF6B7280),
  outlineVariant: Color(0xFFD1D5DB),
  shadow: Colors.black,
  scrim: Colors.black,
  inverseSurface: obsidianDark,
  onInverseSurface: softChalk,
  inversePrimary: Color(0xFFA5B4FC),
  surfaceTint: Color(0xFF4F46E5),
  surfaceDim: Color(0xFFE5E7EB),
  surfaceBright: Colors.white,
  surfaceContainerLowest: Colors.white,
  surfaceContainerLow: Color(0xFFF3F4F6),
  surfaceContainer: Color(0xFFEEF0F4),
  surfaceContainerHigh: Color(0xFFE8EBF0),
  surfaceContainerHighest: Color(0xFFE1E5EB),
);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = dark ? _darkScheme : _lightScheme;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    extensions: [dark ? NomadColors.dark : NomadColors.light],
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      indicatorColor: scheme.secondaryContainer,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(color: scheme.surfaceContainer, surfaceTintColor: Colors.transparent),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: 0.4),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
  );
}

/// Police à chasse fixe pour le terminal : « monospace » est résolu sur
/// Android/Linux, les replis couvrent Windows et macOS.
const TextStyle monoTextStyle = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['Cascadia Mono', 'Consolas', 'Menlo', 'DejaVu Sans Mono', 'Roboto Mono'],
  fontSize: 13,
  height: 1.35,
);
