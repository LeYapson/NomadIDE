import 'package:flutter/material.dart';

ThemeData buildTheme(Brightness brightness) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00897B), brightness: brightness),
    visualDensity: VisualDensity.adaptivePlatformDensity,
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
