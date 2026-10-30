import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../app/settings.dart';
import '../../flash/application/firmware_controller.dart' show firmwareSourceProvider;
import '../../flash/data/firmware_catalog.dart' show FirmwareSource;

/// Vrai dans les tests (voir `test/flutter_test_config.dart`) : pas de requête réseau au démarrage.
bool debugSkipUpdateCheck = false;

/// Une version publiée sur GitHub.
@immutable
class AppRelease {
  const AppRelease({required this.version, required this.url, required this.prerelease});

  /// Sans le « v » du tag : « 0.2.0 », « 0.2.0-beta.1 ».
  final String version;
  final Uri url;
  final bool prerelease;
}

/// Compare deux versions sémantiques (« 0.1.0 », « 0.2.0-beta.1 ») : négatif si [a] est plus ancienne.
/// Une pré-version passe avant la version finale du même numéro (0.2.0-beta < 0.2.0).
int compareVersions(String a, String b) {
  (List<int>, String?) parse(String v) {
    final clean = v.trim().replaceFirst(RegExp('^v'), '').split('+').first;
    final dash = clean.indexOf('-');
    final core = dash < 0 ? clean : clean.substring(0, dash);
    final pre = dash < 0 ? null : clean.substring(dash + 1);
    final numbers = core.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return (numbers, pre);
  }

  final (na, pa) = parse(a);
  final (nb, pb) = parse(b);
  for (var i = 0; i < 3; i++) {
    if (na[i] != nb[i]) return na[i].compareTo(nb[i]);
  }
  if (pa == pb) return 0;
  if (pa == null) return 1;
  if (pb == null) return -1;
  return pa.compareTo(pb);
}

/// Dernière version publiée du dépôt, pré-versions comprises (l'app est en bêta).
class UpdateChecker {
  UpdateChecker(this._source);

  final FirmwareSource _source;

  static final Uri releasesUrl = Uri.https('api.github.com', '/repos/LeYapson/NomadIDE/releases', {'per_page': '10'});

  /// La plus récente des releases publiées (hors brouillons), ou null s'il n'y en a aucune.
  Future<AppRelease?> latest() async {
    final json = jsonDecode(await _source.fetchText(releasesUrl));
    if (json is! List) return null;
    AppRelease? best;
    for (final r in json.whereType<Map<String, Object?>>()) {
      if (r['draft'] == true) continue;
      final tag = r['tag_name'];
      final url = r['html_url'];
      if (tag is! String || url is! String) continue;
      final release = AppRelease(version: tag.replaceFirst(RegExp('^v'), ''), url: Uri.parse(url), prerelease: r['prerelease'] == true);
      if (best == null || compareVersions(release.version, best.version) > 0) best = release;
    }
    return best;
  }
}

final updateCheckerProvider = Provider<UpdateChecker>((ref) => UpdateChecker(ref.watch(firmwareSourceProvider)));

/// Version installée (« 0.1.0 »). Remplaçable dans les tests.
final installedVersionProvider = FutureProvider<String>((ref) async => (await PackageInfo.fromPlatform()).version);

enum UpdateStatus { unknown, checking, upToDate, available, failed }

@immutable
class UpdateState {
  const UpdateState({this.status = UpdateStatus.unknown, this.release, this.installed});

  final UpdateStatus status;

  /// Version plus récente disponible (statut [UpdateStatus.available]).
  final AppRelease? release;
  final String? installed;
}

final updateProvider = NotifierProvider<UpdateController, UpdateState>(UpdateController.new);

/// Vérifie s'il existe une version plus récente. Seule requête : la liste publique des releases GitHub ;
/// rien n'est envoyé sur l'utilisateur ni sur sa machine.
class UpdateController extends Notifier<UpdateState> {
  @override
  UpdateState build() => const UpdateState();

  /// Vérification au démarrage : seulement si le réglage l'autorise, une fois par session.
  Future<void> checkAtStartup() async {
    if (debugSkipUpdateCheck || !ref.read(settingsProvider).checkUpdates || state.status != UpdateStatus.unknown) return;
    await check();
  }

  Future<void> check() async {
    if (state.status == UpdateStatus.checking) return;
    state = UpdateState(status: UpdateStatus.checking, installed: state.installed);
    try {
      final installed = await ref.read(installedVersionProvider.future);
      final latest = await ref.read(updateCheckerProvider).latest();
      if (!ref.mounted) return;
      final newer = latest != null && compareVersions(latest.version, installed) > 0;
      state = UpdateState(
        status: newer ? UpdateStatus.available : UpdateStatus.upToDate,
        release: newer ? latest : null,
        installed: installed,
      );
    } catch (_) {
      // Hors ligne, GitHub injoignable ou réponse inattendue : rien de grave, on réessaiera.
      if (ref.mounted) state = UpdateState(status: UpdateStatus.failed, installed: state.installed);
    }
  }
}
