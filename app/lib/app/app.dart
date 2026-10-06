import 'package:flutter/material.dart';

import 'home_shell.dart';
import 'theme.dart';

class NomadApp extends StatelessWidget {
  const NomadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NomadMCU',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      // Étape 1 : le moniteur série est l'écran unique. Un shell (éditeur,
      // explorateur de carte, flasheur) viendra l'englober à l'étape 2.
      home: const HomeShell(),
    );
  }
}
