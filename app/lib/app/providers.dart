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

enum HomeTab { monitor, micropython, editor, flash, settings }

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
  Directory? fallback;
  try {
    fallback = Directory(p.join((await getApplicationSupportDirectory()).path, 'NomadIDE'));
  } catch (_) {
    // pas de dossier de données : seul Documents reste possible
  }
  return resolveStorageRoot(await getApplicationDocumentsDirectory(), fallback: fallback);
});

/// Dossier `NomadIDE` dans les documents. L'app s'appelait `NomadMCU` : si ce dossier existe encore,
/// il est renommé pour que les projets et brouillons existants restent là ; si le renommage échoue,
/// l'ancien dossier continue d'être utilisé plutôt que de perdre les projets de vue.
///
/// Certains systèmes interdisent aux applications de créer des dossiers dans Documents (par exemple
/// l'« accès contrôlé aux dossiers » de Windows) : si [fallback] est fourni, il prend le relais, et
/// reste utilisé ensuite pour que les projets ne changent pas d'endroit d'un lancement à l'autre.
Future<Directory> resolveStorageRoot(Directory documents, {Directory? fallback}) async {
  final current = Directory(p.join(documents.path, 'NomadIDE'));
  final legacy = Directory(p.join(documents.path, 'NomadMCU'));
  if (await current.exists()) return current;
  if (fallback != null && await fallback.exists()) return fallback;
  if (await legacy.exists()) {
    try {
      return await legacy.rename(current.path);
    } on FileSystemException {
      return legacy;
    }
  }
  if (fallback == null) return current;
  try {
    await current.create(recursive: true);
    return current;
  } on FileSystemException {
    await fallback.create(recursive: true);
    return fallback;
  }
}

final projectStoreProvider = FutureProvider<ProjectStore>((ref) async => ProjectStore(await ref.watch(storageRootProvider.future)));

final draftStoreProvider = FutureProvider<DraftStore>((ref) async => DraftStore(await ref.watch(storageRootProvider.future)));

/// Délai entre la dernière frappe et l'écriture du brouillon sur disque.
final draftDelayProvider = Provider<Duration>((ref) => const Duration(milliseconds: 800));
