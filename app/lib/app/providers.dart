import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_hal/nomad_hal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../features/projects/data/draft_store.dart';
import '../features/projects/data/project_store.dart';

/// `--dart-define=NOMAD_FAKE_SERIAL=true` : carte simulée (dev UI sans matériel, démo iOS).
const bool kSimulateSerial = bool.fromEnvironment('NOMAD_FAKE_SERIAL');

/// Transport série de la plateforme : point d'injection unique de la HAL.
///
/// Dans les tests : `serialTransportProvider.overrideWithValue(FakeSerialTransport())`.
final serialTransportProvider = Provider<SerialTransport>((ref) {
  final transport = createPlatformTransport(simulate: kSimulateSerial);
  ref.onDispose(transport.dispose);
  return transport;
});

enum HomeTab { monitor, micropython, editor, settings }

/// Onglet actif de la coque : les fonctionnalités s'y renvoient mutuellement
/// (ex. ouvrir un fichier de la carte dans l'éditeur).
final homeTabProvider = NotifierProvider<HomeTabController, HomeTab>(HomeTabController.new);

class HomeTabController extends Notifier<HomeTab> {
  @override
  HomeTab build() => HomeTab.monitor;

  void show(HomeTab tab) => state = tab;
}

/// Dossier de données de l'application (projets et brouillons).
///
/// Dans les tests : `storageRootProvider.overrideWith((ref) => tempDir)`.
final storageRootProvider = FutureProvider<Directory>((ref) async {
  final documents = await getApplicationDocumentsDirectory();
  return Directory(p.join(documents.path, 'NomadMCU'));
});

final projectStoreProvider = FutureProvider<ProjectStore>((ref) async => ProjectStore(await ref.watch(storageRootProvider.future)));

final draftStoreProvider = FutureProvider<DraftStore>((ref) async => DraftStore(await ref.watch(storageRootProvider.future)));

/// Délai entre la dernière frappe et l'écriture du brouillon sur disque.
final draftDelayProvider = Provider<Duration>((ref) => const Duration(milliseconds: 800));
