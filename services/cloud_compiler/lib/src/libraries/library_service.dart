import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:path/path.dart' as p;

import 'builtin_headers.dart';
import 'library_cache.dart';
import 'library_index.dart';

/// Renvoie le texte JSON de l'index officiel (déjà décompressé).
typedef IndexFetcher = Future<String> Function();

/// Catalogue des bibliothèques du service : l'index en mémoire, tenu à jour, et le cache d'installation.
class LibraryService {
  LibraryService({
    required this.indexFile,
    required this.fetch,
    required this.cache,
    this.builtin = BuiltinCatalog.empty,
    this.maxAge = const Duration(hours: 24),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final File indexFile;
  final IndexFetcher fetch;
  final LibraryCache cache;
  final Duration maxAge;
  final DateTime Function() _now;

  /// Ce que les cœurs de cartes fournissent déjà ; rempli après le démarrage.
  BuiltinCatalog builtin;

  /// En-têtes (noms de fichiers) de chaque version déjà ouverte, pour ne regarder une bibliothèque qu'une fois.
  final Map<String, Set<String>> _headerSets = {};

  LibraryIndex? _index;
  DateTime? _updatedAt;
  Timer? _timer;
  Future<void>? _refreshing;

  /// L'index, ou null tant qu'il n'a jamais pu être chargé (ni du disque ni d'Arduino).
  LibraryIndex? get index => _index;

  /// Charge l'index gardé sur le disque (le service répond tout de suite), puis le rafraîchit s'il est absent
  /// ou périmé. Un échec de téléchargement n'empêche pas de servir l'ancien index.
  Future<void> start() async {
    if (indexFile.existsSync()) {
      try {
        _index = LibraryIndex.parse(await indexFile.readAsString());
        _updatedAt = indexFile.lastModifiedSync();
      } on Object {
        // fichier abîmé : on le retélécharge
      }
    }
    if (_index == null || _isStale) await refresh().catchError((_) {});
    _timer = Timer.periodic(const Duration(hours: 1), (_) {
      if (_isStale) refresh().catchError((_) {});
    });
  }

  bool get _isStale => _updatedAt == null || _now().difference(_updatedAt!) > maxAge;

  /// Télécharge l'index et le remplace s'il est lisible. Plusieurs appels simultanés n'en font qu'un.
  Future<void> refresh() => _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<void> _refresh() async {
    final text = await fetch();
    final parsed = LibraryIndex.parse(text);
    if (parsed.libraryCount == 0) throw const FormatException('Index de bibliothèques vide.');
    indexFile.parent.createSync(recursive: true);
    final temp = File('${indexFile.path}.tmp');
    await temp.writeAsString(text);
    await temp.rename(indexFile.path);
    _index = parsed;
    _updatedAt = _now();
  }

  void dispose() => _timer?.cancel();

  /// Bibliothèques qui fournissent [header]. Celles que l'index déclare sont sûres ; les autres viennent du nom, et
  /// leur archive est ouverte (installée dans le cache) pour confirmer, dans la limite de [budget] ouvertures par
  /// demande. Les confirmées passent d'abord.
  Future<HeaderResolution> resolveHeader(String header, {CompileBoard? board, VerifyBudget? budget, int limit = 5}) async {
    final index = _index;
    if (index == null) return const HeaderResolution(candidates: [], confirmed: {});
    final architecture = board?.architecture;
    final declared = index.providersOf(header, architecture: architecture);
    final declaredNames = {for (final d in declared) d.name};
    final byName = [
      for (final c in index.nameCandidates(header, architecture: architecture))
        if (!declaredNames.contains(c.name)) c,
    ];

    // Les en-têtes des bibliothèques déjà ouvertes sont connus : c'est ainsi qu'on retrouve `DHT_U.h` (dont le nom
    // ne ressemble pas à celui de sa bibliothèque) une fois `DHT sensor library` ouverte pour `DHT.h`.
    final wanted = _baseName(header).toLowerCase();
    final known = [
      for (final entry in _headerSets.entries)
        if (entry.value.contains(wanted) && index.canonicalName(entry.key.split('@').first) != null)
          index.summary(entry.key.split('@').first),
    ];

    final confirmed = <String>{...declaredNames, for (final k in known) k.name};
    final verified = <String>{};
    final pool = budget ?? VerifyBudget(3);
    // Trois ouvertures en parallèle au plus : c'est un téléchargement chacune.
    final queue = [...byName];
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final candidate = queue.removeAt(0);
        if (confirmed.contains(candidate.name)) continue; // déjà établi : rien à ouvrir
        if (!pool.take()) return;
        final release = index.latest(candidate.name, architecture: architecture);
        if (release == null) continue;
        try {
          final headers = await _headersOf(release).timeout(const Duration(seconds: 25));
          if (headers.contains(_baseName(header).toLowerCase())) verified.add(candidate.name);
        } on Object {
          // téléchargement impossible : le candidat reste une simple suggestion
        }
      }
    }

    await Future.wait([for (var i = 0; i < 3; i++) worker()]);
    confirmed.addAll(verified);

    // Confirmées d'abord ; puis la ressemblance du nom, l'éditeur connu et le nombre de versions.
    final all = {for (final c in [...declared, ...known, ...byName]) c.name: c}.values.toList();
    all.sort((a, b) {
      final byConfirmed = (confirmed.contains(a.name) ? 0 : 1).compareTo(confirmed.contains(b.name) ? 0 : 1);
      if (byConfirmed != 0) return byConfirmed;
      final byName = index.nameScore(header, b.name).compareTo(index.nameScore(header, a.name));
      if (byName != 0) return byName;
      final byTrust = index.trustRank(b.name).compareTo(index.trustRank(a.name));
      if (byTrust != 0) return byTrust;
      final byVersions = b.versionCount.compareTo(a.versionCount);
      return byVersions != 0 ? byVersions : a.name.compareTo(b.name);
    });
    final ordered = all;
    return HeaderResolution(candidates: ordered.take(limit).toList(), confirmed: confirmed);
  }

  Future<Set<String>> _headersOf(LibraryRelease release) async {
    final key = '${release.name}@${release.version}';
    final known = _headerSets[key];
    if (known != null) return known;
    final dir = await cache.ensure(release);
    final headers = <String>{};
    var seen = 0;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (++seen > 5000) break;
      if (entity is! File) continue;
      final name = p.basename(entity.path).toLowerCase();
      if (name.endsWith('.h') || name.endsWith('.hpp') || name.endsWith('.hh')) headers.add(name);
    }
    return _headerSets[key] = headers;
  }

  static String _baseName(String header) => header.split('/').last;
}

/// Résultat de [LibraryService.resolveHeader].
class HeaderResolution {
  const HeaderResolution({required this.candidates, required this.confirmed});

  final List<LibrarySummary> candidates;

  /// Noms des candidats dont l'en-tête est établi (déclaré par l'index ou trouvé dans l'archive).
  final Set<String> confirmed;
}

/// Nombre d'archives qu'une même demande peut ouvrir pour vérifier des candidats (chaque ouverture est un téléchargement).
class VerifyBudget {
  VerifyBudget(this._remaining);

  int _remaining;

  bool take() {
    if (_remaining <= 0) return false;
    _remaining--;
    return true;
  }
}

/// Télécharge l'index officiel (`library_index.json.gz`) et le décompresse.
IndexFetcher httpIndexFetcher(Uri url, {Duration timeout = const Duration(minutes: 2), int maxBytes = 120 * 1024 * 1024}) {
  return () async {
    final bytes = await _httpGet(url, allowedHosts: {url.host}, timeout: timeout, maxBytes: maxBytes);
    final raw = url.path.endsWith('.gz') ? gzip.decode(bytes) : bytes;
    return utf8.decode(raw);
  };
}

/// Téléchargeur des archives de bibliothèques : HTTPS seulement, redirections suivies à la main et
/// refusées si elles quittent les hôtes autorisés.
LibraryDownloader httpLibraryDownloader({Set<String> allowedHosts = const {'downloads.arduino.cc'}, Duration timeout = const Duration(minutes: 2)}) {
  return (url, {required maxBytes}) => _httpGet(url, allowedHosts: allowedHosts, timeout: timeout, maxBytes: maxBytes);
}

Future<Uint8List> _httpGet(Uri url, {required Set<String> allowedHosts, required Duration timeout, required int maxBytes}) async {
  final client = HttpClient()
    ..connectionTimeout = timeout
    ..userAgent = 'NomadIDE-compiler';
  try {
    var current = url;
    for (var hop = 0; hop < 4; hop++) {
      if (current.scheme != 'https' || !allowedHosts.contains(current.host)) {
        throw LibraryInstallException('Adresse refusée : ${current.host}.');
      }
      final request = await client.getUrl(current).timeout(timeout);
      request.followRedirects = false;
      final response = await request.close().timeout(timeout);
      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>();
        if (location == null) throw LibraryInstallException('Redirection invalide.');
        current = current.resolve(location);
        continue;
      }
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw LibraryInstallException('Réponse ${response.statusCode} de ${current.host}.');
      }
      final out = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        out.add(chunk);
        if (out.length > maxBytes) throw LibraryInstallException('Téléchargement trop volumineux.');
      }
      return out.takeBytes();
    }
    throw LibraryInstallException('Trop de redirections.');
  } finally {
    client.close(force: true);
  }
}

/// Fichier de l'index dans le dossier de travail du service.
File defaultIndexFile(String workDir) => File(p.join(workDir, 'library_index.json'));
