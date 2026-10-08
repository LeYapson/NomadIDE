import 'package:file_selector/file_selector.dart';

import '../application/flash_controller.dart';

/// Sélecteur de fichiers du système, limité aux `.uf2`.
Future<PickedFile?> pickUf2WithSystemDialog() async {
  final file = await openFile(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'UF2', extensions: ['uf2']),
    ],
  );
  if (file == null) return null;
  return (name: file.name, bytes: await file.readAsBytes());
}
