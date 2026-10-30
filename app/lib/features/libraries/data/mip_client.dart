import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../flash/data/firmware_catalog.dart' show FirmwareException, FirmwareSource;

/// Une bibliothèque de l'index `micropython-lib`.
class MipPackage {
  const MipPackage({
    required this.name,
    required this.version,
    this.description = '',
    this.license = '',
    this.author = '',
    this.versions = const {},
  });

  factory MipPackage.fromJson(Map<String, Object?> json) => MipPackage(
        name: json['name'] as String,
        version: json['version'] as String? ?? 'latest',
        description: json['description'] as String? ?? '',
        license: json['license'] as String? ?? '',
        author: json['author'] as String? ?? '',
        versions: {
          for (final MapEntry(:key, :value) in (json['versions'] as Map<String, Object?>? ?? const {}).entries)
            key: [for (final v in value as List<Object?>) v as String],
        },
      );

  final String name;
  final String version;
  final String description;
  final String license;
  final String author;

  /// Versions publiées par format : `py` (sources) et un numéro de format `.mpy` (« 6 »).
  final Map<String, List<String>> versions;

  /// Format à télécharger pour une carte qui charge les `.mpy` de version [mpy] : compilé s'il existe
  /// pour cette version (plus petit et plus rapide à charger), sinon les sources.
  String formatFor(int mpy) => mpy > 0 && (versions['$mpy']?.contains(version) ?? false) ? '$mpy' : 'py';
}

/// L'index `micropython-lib` (protocole `mip`, version 2).
class MipIndex {
  const MipIndex(this.packages);

  factory MipIndex.parse(String text) {
    final json = jsonDecode(text) as Map<String, Object?>;
    final packages = [for (final p in json['packages'] as List<Object?>) MipPackage.fromJson(p as Map<String, Object?>)]
      ..sort((a, b) => a.name.compareTo(b.name));
    return MipIndex(packages);
  }

  final List<MipPackage> packages;

  MipPackage? byName(String name) => packages.where((p) => p.name == name).firstOrNull;

  /// Bibliothèques dont le nom ou la description contient [query] ; celles dont le nom commence par
  /// la recherche d'abord.
  List<MipPackage> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return packages;
    final matches = packages
        .where((p) => p.name.toLowerCase().contains(q) || p.description.toLowerCase().contains(q))
        .toList();
    int rank(MipPackage p) => p.name.toLowerCase().startsWith(q) ? 0 : (p.name.toLowerCase().contains(q) ? 1 : 2);
    matches.sort((a, b) => rank(a) != rank(b) ? rank(a).compareTo(rank(b)) : a.name.compareTo(b.name));
    return matches;
  }
}

/// Description d'un paquet (`package.json`) : ses fichiers et ses dépendances.
class MipManifest {
  const MipManifest({this.version, this.hashes = const [], this.urls = const [], this.deps = const []});

  factory MipManifest.parse(String text) {
    final json = jsonDecode(text) as Map<String, Object?>;
    List<(String, String)> pairs(String key) => [
          for (final e in json[key] as List<Object?>? ?? const [])
            ((e as List<Object?>)[0] as String, e.length > 1 ? e[1] as String : 'latest'),
        ];
    return MipManifest(
      version: json['version'] as String?,
      hashes: pairs('hashes'),
      urls: pairs('urls'),
      deps: pairs('deps'),
    );
  }

  final String? version;

  /// (chemin dans `/lib`, empreinte courte) : fichiers hébergés par l'index.
  final List<(String, String)> hashes;

  /// (chemin dans `/lib`, adresse) : fichiers hébergés ailleurs (GitHub…).
  final List<(String, String)> urls;

  /// (nom ou adresse du paquet, version).
  final List<(String, String)> deps;
}

/// Un fichier prêt à être copié sur la carte, à [path] sous `/lib`.
class MipFile {
  const MipFile(this.path, this.bytes);

  final String path;
  final Uint8List bytes;
}

enum MipError { network, notFound, badPackage, insecure }

class MipException implements Exception {
  const MipException(this.error, {required this.target, this.cause});

  final MipError error;

  /// Ce qui était demandé (nom du paquet, adresse).
  final String target;
  final Object? cause;

  @override
  String toString() => 'MipException($error, $target${cause == null ? '' : ', $cause'})';
}

/// Cache local : l'index et les fichiers déjà téléchargés restent disponibles hors ligne. Les fichiers
/// de l'index sont rangés par empreinte : leur contenu ne change jamais.
class MipCache {
  MipCache(this.directory);

  final Directory directory;

  File get _index => File('${directory.path}/index.json');
  File _file(String hash) => File('${directory.path}/files/$hash');

  Future<String?> readIndex() async => await _index.exists() ? _index.readAsString() : null;

  Future<void> writeIndex(String text) async {
    await directory.create(recursive: true);
    await _index.writeAsString(text);
  }

  Future<Uint8List?> readFile(String hash) async => await _file(hash).exists() ? _file(hash).readAsBytes() : null;

  Future<void> writeFile(String hash, Uint8List bytes) async {
    final f = _file(hash);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
  }
}

/// Résout et télécharge une bibliothèque MicroPython comme le fait `mip` sur la carte : depuis l'index
/// `micropython-lib`, ou depuis GitHub (`github:auteur/dépôt`) ou une adresse HTTPS. Le téléchargement
/// se fait ici, sur l'appareil : la carte n'a besoin ni de Wi-Fi ni de `mip`.
class MipClient {
  MipClient(this._source, {this.cache, Uri? index}) : index = index ?? defaultIndex;

  /// Index officiel (`_PACKAGE_INDEX` de `mip`).
  static final Uri defaultIndex = Uri.https('micropython.org', '/pi/v2');

  final FirmwareSource _source;
  final MipCache? cache;
  final Uri index;

  /// L'index, depuis le réseau, ou depuis le cache s'il n'est pas joignable.
  Future<({MipIndex index, bool offline})> loadIndex() async {
    try {
      final text = await _text(_under(index, 'index.json'), 'index');
      try {
        await cache?.writeIndex(text);
      } on FileSystemException {
        // Cache non écrit : sans conséquence.
      }
      return (index: _parse(() => MipIndex.parse(text), 'index'), offline: false);
    } on MipException catch (e) {
      if (e.error != MipError.network) rethrow;
      final cached = await cache?.readIndex();
      if (cached == null) rethrow;
      return (index: _parse(() => MipIndex.parse(cached), 'index'), offline: true);
    }
  }

  /// Tous les fichiers de [spec] et de ses dépendances. [spec] : nom d'un paquet de l'index
  /// (`ssd1306`, `requests@0.10.0`), `github:auteur/dépôt[/chemin][@branche]`, ou adresse HTTPS d'un
  /// `package.json` ou d'un fichier `.py`/`.mpy`. [mpy] : version `.mpy` de la carte (0 : sources).
  Future<List<MipFile>> resolve(String spec, {required int mpy, MipIndex? catalog, void Function(String file)? onFile}) async {
    final files = <String, MipFile>{};
    final (name, version) = _splitVersion(spec.trim());
    await _install(name, version, mpy: mpy, catalog: catalog, files: files, seen: {}, onFile: onFile);
    return files.values.toList();
  }

  Future<void> _install(
    String name,
    String? version, {
    required int mpy,
    required MipIndex? catalog,
    required Map<String, MipFile> files,
    required Set<String> seen,
    void Function(String file)? onFile,
  }) async {
    if (!seen.add(name)) return; // dépendance déjà traitée (ou cycle)
    final Uri manifestUrl;
    if (_isRemote(name)) {
      final url = _rewrite(name, version);
      final path = url.path.toLowerCase();
      if (path.endsWith('.py') || path.endsWith('.mpy')) {
        final file = url.pathSegments.last;
        onFile?.call(file);
        files[file] = MipFile(file, await _bytes(url, name));
        return;
      }
      manifestUrl = path.endsWith('.json') ? url : url.replace(path: '${url.path}/package.json');
    } else {
      final package = catalog?.byName(name);
      if (catalog != null && package == null) throw MipException(MipError.notFound, target: name);
      final format = package?.formatFor(mpy) ?? 'py';
      manifestUrl = _under(index, 'package/$format/$name/${version ?? 'latest'}.json');
    }

    final manifestBytes = await _bytes(manifestUrl, name);
    final resolved = _parse(() => MipManifest.parse(_utf8(manifestBytes)), name);
    final base = manifestUrl.replace(pathSegments: [...manifestUrl.pathSegments]..removeLast());

    for (final (path, hash) in resolved.hashes) {
      onFile?.call(path);
      files[path] = MipFile(path, await _hashed(hash, name));
    }
    for (final (path, url) in resolved.urls) {
      onFile?.call(path);
      final target = _isRemote(url) ? _rewrite(url, version) : base.replace(pathSegments: [...base.pathSegments, ...url.split('/')]);
      files[path] = MipFile(path, await _bytes(target, name));
    }
    for (final (dep, depVersion) in resolved.deps) {
      await _install(dep, depVersion == 'latest' ? null : depVersion,
          mpy: mpy, catalog: _isRemote(dep) ? null : catalog, files: files, seen: seen, onFile: onFile);
    }
  }

  /// Analyse une réponse ; une description illisible devient [MipError.badPackage].
  T _parse<T>(T Function() parse, String target) {
    try {
      return parse();
    } on FormatException catch (e) {
      throw MipException(MipError.badPackage, target: target, cause: e);
    } on TypeError catch (e) {
      throw MipException(MipError.badPackage, target: target, cause: e);
    }
  }

  /// Fichier hébergé par l'index (`/file/ab/abcdef12`), lu dans le cache s'il y est déjà.
  Future<Uint8List> _hashed(String hash, String target) async {
    final cached = await cache?.readFile(hash);
    if (cached != null) return cached;
    final prefix = hash.length >= 2 ? hash.substring(0, 2) : hash;
    final bytes = await _bytes(_under(index, 'file/$prefix/$hash'), target);
    try {
      await cache?.writeFile(hash, bytes);
    } on FileSystemException {
      // Cache non écrit : sans conséquence.
    }
    return bytes;
  }

  Future<String> _text(Uri url, String target) async => _utf8(await _bytes(url, target));

  static String _utf8(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);

  Future<Uint8List> _bytes(Uri url, String target) async {
    if (url.scheme != 'https') throw MipException(MipError.insecure, target: url.toString());
    try {
      return await _source.fetchBytes(url);
    } on FirmwareException catch (e) {
      final notFound = e.status == 404;
      throw MipException(notFound ? MipError.notFound : MipError.network, target: target, cause: e);
    }
  }

  static Uri _under(Uri base, String path) => base.replace(pathSegments: [...base.pathSegments.where((s) => s.isNotEmpty), ...path.split('/')]);

  static bool _isRemote(String spec) => spec.startsWith('github:') || spec.startsWith('https://') || spec.startsWith('http://');

  /// `github:auteur/dépôt/chemin` → `https://raw.githubusercontent.com/auteur/dépôt/<branche>/chemin`
  /// (branche par défaut : `HEAD`), comme `_rewrite_url` de `mip`.
  static Uri _rewrite(String url, String? branch) {
    if (url.startsWith('github:')) {
      final parts = url.substring('github:'.length).split('/');
      if (parts.length < 2) throw MipException(MipError.notFound, target: url);
      return Uri.https('raw.githubusercontent.com', [parts[0], parts[1], branch ?? 'HEAD', ...parts.skip(2)].join('/'));
    }
    return Uri.parse(url);
  }

  /// `nom@version` → (nom, version). Le `@` d'une adresse (`https://a@b/…`) n'est pas une version.
  static (String, String?) _splitVersion(String spec) {
    final at = spec.lastIndexOf('@');
    if (at <= 0 || spec.substring(at).contains('/')) return (spec, null);
    return (spec.substring(0, at), spec.substring(at + 1));
  }
}
