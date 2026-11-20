/// Composants d'interface communs, organisés par niveau (atomic design) :
///  - `atoms/` : éléments indivisibles (bouton d'action matérielle, pastille d'étape, titre de section) ;
///  - `molecules/` : atomes assemblés pour un rôle précis (étape repliable, bannière de résultat,
///    section avancée, progression, liste des cartes).
/// Les écrans (`features/*/presentation`) assemblent ces composants ; les couleurs viennent du thème.
library;

export 'atoms/hardware_button.dart';
export 'atoms/section_header.dart';
export 'atoms/step_badge.dart';
export 'molecules/board_dropdown.dart';
export 'molecules/disclosure.dart';
export 'molecules/progress_status.dart';
export 'molecules/status_banner.dart';
export 'molecules/step_card.dart';
