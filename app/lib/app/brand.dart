import 'package:flutter/material.dart';

/// Logo de NomadIDE. Décoratif : le nom de l'app est déjà dit par le texte à côté, le lecteur d'écran l'ignore.
class NomadLogo extends StatelessWidget {
  const NomadLogo({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Image.asset('assets/brand/nomad_logo.png', width: size, height: size, filterQuality: FilterQuality.medium),
      );
}
