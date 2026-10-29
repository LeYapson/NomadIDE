/// Composants d'interface communs, organisés par niveau (atomic design) :
///  - `atoms/` : éléments indivisibles (bouton d'action matérielle, pastille d'étape) ;
///  - `molecules/` : atomes assemblés pour un rôle précis (étape repliable, bannière de résultat,
///    section avancée, progression).
/// Les écrans (`features/*/presentation`) assemblent ces composants ; les couleurs viennent du thème.
library;

export 'atoms/hardware_button.dart';
export 'atoms/step_badge.dart';
export 'molecules/disclosure.dart';
export 'molecules/progress_status.dart';
export 'molecules/status_banner.dart';
export 'molecules/step_card.dart';
