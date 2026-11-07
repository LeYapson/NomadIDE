import '../../../l10n/l10n.dart';
import '../../flash/application/flash_controller.dart' show flashSizeLabel;
import '../application/compile_controller.dart';
import '../data/compile_api.dart';

/// Texte d'un problème de compilation, dans la langue de l'utilisateur.
String compileProblemMessage(AppLocalizations l10n, CompileProblem problem, String? detail) => switch (problem) {
      CompileProblem.notConfigured => l10n.ccProbNotConfigured,
      CompileProblem.badUrl => l10n.ccProbBadUrl,
      CompileProblem.unreachable => l10n.ccProbUnreachable,
      CompileProblem.timeout => l10n.ccProbTimeout,
      CompileProblem.unauthorized => l10n.ccProbUnauthorized,
      CompileProblem.rejected => l10n.ccProbRejected(detail ?? ''),
      CompileProblem.tooLarge => l10n.ccProbTooLarge(flashSizeLabel(l10n, int.tryParse(detail ?? '') ?? 0)),
      CompileProblem.queueFull => l10n.ccProbQueueFull,
      CompileProblem.librariesUnavailable => l10n.ccProbLibrariesUnavailable,
      CompileProblem.expired => l10n.ccProbExpired,
      CompileProblem.badResponse => l10n.ccProbBadResponse,
      CompileProblem.noSketch => l10n.ccProbNoSketch,
      CompileProblem.severalSketches => l10n.ccProbSeveralSketches(detail ?? ''),
      CompileProblem.saveFailed => l10n.ccProbSaveFailed,
      CompileProblem.readFailed => l10n.ccProbReadFailed(detail ?? ''),
      CompileProblem.downloadFailed => l10n.ccProbDownloadFailed,
      CompileProblem.checksum => l10n.ccProbChecksum,
    };

/// Texte d'une erreur d'échange avec le service (test de connexion dans les réglages).
String compileApiErrorMessage(AppLocalizations l10n, CompileApiException e) => compileProblemMessage(
      l10n,
      switch (e.kind) {
        CompileErrorKind.badUrl => CompileProblem.badUrl,
        CompileErrorKind.unreachable => CompileProblem.unreachable,
        CompileErrorKind.timeout => CompileProblem.timeout,
        CompileErrorKind.unauthorized => CompileProblem.unauthorized,
        CompileErrorKind.rejected => CompileProblem.rejected,
        CompileErrorKind.tooLarge => CompileProblem.tooLarge,
        CompileErrorKind.queueFull => CompileProblem.queueFull,
        CompileErrorKind.unavailable => CompileProblem.librariesUnavailable,
        CompileErrorKind.notFound => CompileProblem.expired,
        CompileErrorKind.badResponse => CompileProblem.badResponse,
      },
      e.detail,
    );
