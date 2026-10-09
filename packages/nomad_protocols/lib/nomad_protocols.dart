/// NomadMCU — protocoles de communication avec les cartes, en Dart pur.
///
/// Ce package ne dépend ni de Flutter ni de `nomad_hal` : il ne connaît que
/// [ByteLink]. L'application adapte une `SerialConnection` en [ByteLink],
/// et les tests branchent une fausse carte.
library;

export 'src/io/byte_link.dart';
export 'src/io/byte_reader.dart';
export 'src/micropython/micropython_fs.dart';
export 'src/micropython/raw_repl.dart';
export 'src/protocol_exceptions.dart';
export 'src/uf2/uf2_drive.dart';
export 'src/uf2/uf2_file.dart';
export 'src/esp/esp_loader.dart';
export 'src/esp/md5.dart';
export 'src/esp/slip.dart';
