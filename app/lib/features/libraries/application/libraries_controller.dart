import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nomad_protocols/nomad_protocols.dart' show RemoteEntry;

import '../../../app/providers.dart';
import '../../../app/settings.dart';
import '../../../l10n/l10n.dart';
import '../../flash/application/firmware_controller.dart' show firmwareSourceProvider;
import '../../micropython/application/micropython_controller.dart';
import '../data/mip_client.dart';

/// Client `mip`, avec son cache dans le dossier de l'application. Dans les tests : un faux réseau.
final mipClientProvider = FutureProvider<MipClient>((ref) async {
  final storage = await ref.watch(storageRootProvider.future);
  return MipClient(ref.watch(firmwareSourceProvider), cache: MipCache(Directory('${storage.path}/cache/mip')));
});

enum LibIndexStatus { idle, loading, ready, failed }

enum LibPhase { idle, downloading, writing }

@immutable
class LibrariesState {
  const LibrariesState({
    this.status = LibIndexStatus.idle,
    this.index,
    this.offline = false,
    this.query = '',
    this.phase = LibPhase.idle,
    this.busyName,
    this.fileDone = 0,
    this.fileTotal = 0,
    this.message,
    this.succeeded = false,
    this.installed,
  });

  final LibIndexStatus status;
  final MipIndex? index;

  /// Vrai si l'index vient du cache (réseau injoignable).
  final bool offline;
  final String query;
  final LibPhase phase;

  /// Bibliothèque en cours d'installation.
  final String? busyName;
  final int fileDone;
  final int fileTotal;
  final String? message;
  final bool succeeded;

  /// Contenu de `/lib` sur la carte ; null tant qu'il n'a pas été lu.
  final List<RemoteEntry>? installed;

  bool get working => phase != LibPhase.idle;

  List<MipPackage> get results => index?.search(query) ?? const [];

  LibrariesState copyWith({
    LibIndexStatus? status,
    Object? index = _unset,
    bool? offline,
    String? query,
    LibPhase? phase,
    Object? busyName = _unset,
    int? fileDone,
    int? fileTotal,
    Object? message = _unset,
    bool? succeeded,
    Object? installed = _unset,
  }) =>
      LibrariesState(
        status: status ?? this.status,
        index: identical(index, _unset) ? this.index : index as MipIndex?,
        offline: offline ?? this.offline,
        query: query ?? this.query,
        phase: phase ?? this.phase,
        busyName: identical(busyName, _unset) ? this.busyName : busyName as String?,
        fileDone: fileDone ?? this.fileDone,
        fileTotal: fileTotal ?? this.fileTotal,
        message: identical(message, _unset) ? this.message : message as String?,
        succeeded: succeeded ?? this.succeeded,
        installed: identical(installed, _unset) ? this.installed : installed as List<RemoteEntry>?,
      );
}

const Object _unset = Object();

final librariesProvider = NotifierProvider<LibrariesController, LibrariesState>(LibrariesController.new);

/// Bibliothèques MicroPython : chercher dans `micropython-lib`, télécharger sur l'appareil, copier dans
/// `/lib` sur la carte par le raw REPL (fichiers vérifiés), lister et supprimer ce qui est installé.
class LibrariesController extends Notifier<LibrariesState> {
  AppLocalizations get _l10n => ref.read(l10nProvider);

  MicroPythonController get _micro => ref.read(microPythonProvider.notifier);

  @override
  LibrariesState build() => const LibrariesState();

  Future<void> loadIndex() async {
    if (state.status == LibIndexStatus.loading) return;
    state = state.copyWith(status: LibIndexStatus.loading, message: null);
    try {
      final client = await ref.read(mipClientProvider.future);
      final (:index, :offline) = await client.loadIndex();
      if (!ref.mounted) return;
      state = state.copyWith(status: LibIndexStatus.ready, index: index, offline: offline);
    } on MipException catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(status: LibIndexStatus.failed, message: mipErrorMessage(_l10n, e), succeeded: false);
    }
  }

  void setQuery(String query) => state = state.copyWith(query: query);

  /// Installe [spec] (nom dans l'index, `github:auteur/dépôt`, adresse https) et ses dépendances.
  Future<void> install(String spec) async {
    spec = spec.trim();
    if (spec.isEmpty || state.working) return;
    final l10n = _l10n;
    if (!ref.read(microPythonProvider).isReady) {
      state = state.copyWith(message: l10n.libConnectFirst, succeeded: false);
      return;
    }
    final name = displayName(spec);
    state = state.copyWith(phase: LibPhase.downloading, busyName: name, fileDone: 0, fileTotal: 0, message: null);
    try {
      final info = await _micro.storageInfo();
      if (!ref.mounted) return;
      if (info == null) {
        _finish(ref.read(microPythonProvider).errorMessage ?? l10n.libConnectFirst, success: false);
        return;
      }
      final client = await ref.read(mipClientProvider.future);
      final files = await client.resolve(spec, mpy: info.mpy, catalog: state.index);
      if (!ref.mounted) return;

      state = state.copyWith(phase: LibPhase.writing, fileTotal: files.length);
      final ok = await _micro.installLibrary(
        name,
        [for (final f in files) (path: f.path, bytes: f.bytes)],
        onFile: (done, total) {
          if (ref.mounted) state = state.copyWith(fileDone: done, fileTotal: total);
        },
      );
      if (!ref.mounted) return;
      if (!ok) {
        _finish(ref.read(microPythonProvider).errorMessage ?? l10n.libConnectFirst, success: false);
        return;
      }
      _finish(l10n.libInstalled(name, files.length, moduleName(files.first.path)), success: true);
      await refreshInstalled();
    } on MipException catch (e) {
      if (ref.mounted) _finish(mipErrorMessage(l10n, e), success: false);
    }
  }

  void _finish(String message, {required bool success}) =>
      state = state.copyWith(phase: LibPhase.idle, busyName: null, message: message, succeeded: success);

  Future<void> refreshInstalled() async {
    if (!ref.read(microPythonProvider).isReady) return;
    final entries = await _micro.listLibraries();
    if (!ref.mounted || entries == null) return;
    state = state.copyWith(installed: entries);
  }

  Future<void> remove(RemoteEntry entry) async {
    if (state.working) return;
    final ok = await _micro.removeLibrary(entry);
    if (!ref.mounted) return;
    if (ok) state = state.copyWith(message: _l10n.libRemoved(entry.name), succeeded: true);
    await refreshInstalled();
  }

  /// Nom affiché d'une bibliothèque : `github:auteur/bme280@v2` → `bme280`, `…/dht20.py` → `dht20`.
  static String displayName(String spec) {
    var s = spec.trim();
    final at = s.lastIndexOf('@');
    if (at > 0 && !s.substring(at).contains('/')) s = s.substring(0, at);
    if (s.endsWith('/package.json')) s = s.substring(0, s.length - '/package.json'.length);
    final last = s.split(RegExp('[/:]')).where((p) => p.isNotEmpty).lastOrNull ?? s;
    return last.replaceAll(RegExp(r'\.(m?py|json)$'), '');
  }

  /// Module à importer d'après le premier fichier : `aioble/__init__.mpy` → `aioble`, `ssd1306.mpy` → `ssd1306`.
  static String moduleName(String path) => path.split('/').first.replaceAll(RegExp(r'\.m?py$'), '');
}

String mipErrorMessage(AppLocalizations l10n, MipException e) => switch (e.error) {
      MipError.network => l10n.libErrNetwork(e.target),
      MipError.notFound => l10n.libErrNotFound(e.target),
      MipError.badPackage => l10n.libErrBadPackage(e.target),
      MipError.insecure => l10n.libErrInsecure(e.target),
    };
