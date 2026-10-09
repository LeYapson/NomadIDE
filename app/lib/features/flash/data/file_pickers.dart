import 'package:file_selector/file_selector.dart';

import '../application/flash_controller.dart';

Future<PickedFile?> _pick(String label, List<String> extensions) async {
  final file = await openFile(acceptedTypeGroups: [XTypeGroup(label: label, extensions: extensions)]);
  if (file == null) return null;
  return (name: file.name, bytes: await file.readAsBytes());
}

/// Sélecteur de fichiers du système, limité aux `.uf2`.
Future<PickedFile?> pickUf2WithSystemDialog() => _pick('UF2', const ['uf2']);

/// Sélecteur de fichiers du système, limité aux `.bin`.
Future<PickedFile?> pickBinWithSystemDialog() => _pick('BIN', const ['bin']);
