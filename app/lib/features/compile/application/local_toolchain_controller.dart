import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../local/local_compile_api.dart';
import '../local/local_toolchain.dart';

/// La compilation locale n'existe que sur ordinateur : sur mobile, seul le serveur compile.
bool get localCompileAvailable => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// Dossier de l'outillage. Dans les tests : `localToolchainProvider.overrideWith(...)`.
final localToolchainProvider = FutureProvider<LocalToolchain>(retry: (_, __) => null, (ref) async {
  final support = await getApplicationSupportDirectory();
  return LocalToolchain(Directory(p.join(support.path, 'NomadIDE', 'toolchain')));
});

/// Le client qui compile sur cette machine ; null tant que le dossier de l'outillage n'est pas connu.
final localCompileApiProvider = Provider<LocalCompileApi?>((ref) {
  final toolchain = ref.watch(localToolchainProvider).value;
  if (toolchain == null) return null;
  final api = LocalCompileApi(toolchain);
  ref.onDispose(() => unawaited(api.close()));
  return api;
});

enum ToolchainPhase { checking, unsupported, missing, installing, ready, failed }

@immutable
class ToolchainState {
  const ToolchainState({this.phase = ToolchainPhase.checking, this.progress, this.error, this.coresDone = 0});

  final ToolchainPhase phase;
  final ToolchainProgress? progress;
  final String? error;

  /// Nombre de cœurs déjà installés pendant cette installation (pour « 1 sur 2 »).
  final int coresDone;

  ToolchainState copyWith({ToolchainPhase? phase, ToolchainProgress? progress, String? error, int? coresDone}) =>
      ToolchainState(phase: phase ?? this.phase, progress: progress ?? this.progress, error: error, coresDone: coresDone ?? this.coresDone);
}

final toolchainProvider = NotifierProvider<ToolchainController, ToolchainState>(ToolchainController.new);

/// État de l'outillage de compilation locale (arduino-cli et cœurs) et son installation.
class ToolchainController extends Notifier<ToolchainState> {
  CancelSignal? _cancel;

  @override
  ToolchainState build() {
    ref.listen(localToolchainProvider, (_, __) => unawaited(check()));
    Future.microtask(check);
    return const ToolchainState();
  }

  /// Relit le disque : l'outillage est-il complet ?
  Future<void> check() async {
    final toolchain = ref.read(localToolchainProvider).value;
    if (toolchain == null || state.phase == ToolchainPhase.installing) return;
    state = ToolchainState(phase: !toolchain.supported ? ToolchainPhase.unsupported : (toolchain.ready ? ToolchainPhase.ready : ToolchainPhase.missing));
  }

  Future<void> install() async {
    final toolchain = ref.read(localToolchainProvider).value;
    if (toolchain == null || state.phase == ToolchainPhase.installing) return;
    final cancel = _cancel = CancelSignal();
    state = const ToolchainState(phase: ToolchainPhase.installing);
    var done = 0;
    try {
      await for (final progress in toolchain.install(cancel: cancel)) {
        if (!ref.mounted) return;
        if (progress.step == ToolchainStep.installCore && progress.line != null) {
          // une ligne « … esp32:esp32@3.x installed » marque la fin d'un cœur
          if (progress.line!.toLowerCase().contains('installed')) done++;
        }
        state = ToolchainState(phase: ToolchainPhase.installing, progress: progress, coresDone: done);
      }
      await ref.read(localCompileApiProvider)?.toolchainChanged();
      if (ref.mounted) state = const ToolchainState(phase: ToolchainPhase.ready);
    } on ToolchainException catch (e) {
      if (ref.mounted) state = ToolchainState(phase: cancel.cancelled ? ToolchainPhase.missing : ToolchainPhase.failed, error: cancel.cancelled ? null : e.message);
    } on Object catch (e) {
      if (ref.mounted) state = ToolchainState(phase: ToolchainPhase.failed, error: '$e');
    }
  }

  void cancelInstall() => _cancel?.cancel();

  /// Supprime l'outillage pour récupérer l'espace disque.
  Future<void> uninstall() async {
    final toolchain = ref.read(localToolchainProvider).value;
    if (toolchain == null || state.phase == ToolchainPhase.installing) return;
    await ref.read(localCompileApiProvider)?.close();
    await toolchain.uninstall();
    await check();
  }
}
