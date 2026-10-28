import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/settings.dart';
import '../../../l10n/l10n.dart';
import '../data/firmware_catalog.dart';
import 'flash_controller.dart' show PickedFile, flashSizeLabel;

/// Accès réseau. Dans les tests : une fausse source.
final firmwareSourceProvider = Provider<FirmwareSource>((ref) => HttpFirmwareSource());

final firmwareCatalogProvider = Provider<FirmwareCatalog>((ref) => FirmwareCatalog(ref.watch(firmwareSourceProvider)));

enum FirmwarePhase { idle, searching, found, downloading, downloaded, failed }

@immutable
class FirmwareState {
  const FirmwareState({
    this.board,
    this.phase = FirmwarePhase.idle,
    this.release,
    this.done = 0,
    this.total,
    this.message,
  });

  final FirmwareBoard? board;
  final FirmwarePhase phase;
  final FirmwareRelease? release;
  final int done;
  final int? total;

  /// Résultat ou erreur, déjà traduit.
  final String? message;

  bool get busy => phase == FirmwarePhase.searching || phase == FirmwarePhase.downloading;

  double? get fraction => total == null || total! <= 0 ? null : (done / total!).clamp(0.0, 1.0);

  FirmwareState copyWith({
    Object? board = _unset,
    FirmwarePhase? phase,
    Object? release = _unset,
    int? done,
    Object? total = _unset,
    Object? message = _unset,
  }) {
    return FirmwareState(
      board: identical(board, _unset) ? this.board : board as FirmwareBoard?,
      phase: phase ?? this.phase,
      release: identical(release, _unset) ? this.release : release as FirmwareRelease?,
      done: done ?? this.done,
      total: identical(total, _unset) ? this.total : total as int?,
      message: identical(message, _unset) ? this.message : message as String?,
    );
  }
}

const Object _unset = Object();

final firmwareProvider = NotifierProvider<FirmwareController, FirmwareState>(FirmwareController.new);

/// Cherche puis télécharge le firmware MicroPython officiel d'une carte.
///
/// En deux temps volontairement : [find] montre la version et l'adresse exacte, [download] n'est lancé
/// que sur un clic de l'utilisateur. Rien n'est écrit sur une carte ici : le fichier est remis à
/// l'écran de flash, qui le contrôle comme n'importe quel fichier choisi à la main.
class FirmwareController extends Notifier<FirmwareState> {
  AppLocalizations get _l10n => ref.read(l10nProvider);

  @override
  FirmwareState build() => const FirmwareState();

  void selectBoard(FirmwareBoard? board) {
    if (state.busy) return;
    state = FirmwareState(board: board);
  }

  Future<void> find(FirmwareBoard board) async {
    if (state.busy) return;
    state = FirmwareState(board: board, phase: FirmwarePhase.searching);
    try {
      final release = await ref.read(firmwareCatalogProvider).latest(board);
      if (!ref.mounted) return;
      state = state.copyWith(phase: FirmwarePhase.found, release: release);
    } on FirmwareException catch (e) {
      _fail(e, board.label);
    }
  }

  /// Télécharge la version trouvée par [find] ; renvoie le fichier, ou null en cas d'échec.
  Future<PickedFile?> download() async {
    final release = state.release;
    if (release == null || state.busy) return null;
    state = state.copyWith(phase: FirmwarePhase.downloading, done: 0, total: null, message: null);
    try {
      final file = await ref.read(firmwareCatalogProvider).download(
        release,
        onProgress: (done, total) {
          if (ref.mounted) state = state.copyWith(done: done, total: total);
        },
      );
      if (!ref.mounted) return null;
      state = state.copyWith(
        phase: FirmwarePhase.downloaded,
        message: _l10n.fwDownloaded(file.name, flashSizeLabel(_l10n, file.bytes.length)),
      );
      return file;
    } on FirmwareException catch (e) {
      _fail(e, release.board.label);
      return null;
    }
  }

  void _fail(FirmwareException e, String board) {
    if (!ref.mounted) return;
    final l10n = _l10n;
    final message = switch (e.error) {
      FirmwareError.network => l10n.fwNoNetwork(e.host, '${e.cause ?? ''}'),
      FirmwareError.notFound => l10n.fwNotFound(board, e.host),
      FirmwareError.badStatus => l10n.fwBadStatus(e.host, '${e.status}'),
      FirmwareError.tooLarge => l10n.fwTooLarge(flashSizeLabel(l10n, e.size ?? 0)),
      FirmwareError.untrustedSource => l10n.fwUntrusted(e.host),
    };
    state = state.copyWith(phase: FirmwarePhase.failed, message: message);
  }
}
