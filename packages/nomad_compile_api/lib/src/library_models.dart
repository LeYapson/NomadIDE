/// Une bibliothèque Arduino choisie pour un projet : nom (celui de l'index officiel) et version exacte.
class LibraryRef {
  const LibraryRef({required this.name, required this.version});

  final String name;
  final String version;

  Map<String, Object?> toJson() => {'name': name, 'version': version};

  factory LibraryRef.fromJson(Map<String, Object?> json) =>
      LibraryRef(name: json['name'] as String, version: json['version'] as String);

  @override
  bool operator ==(Object other) => other is LibraryRef && other.name == name && other.version == version;

  @override
  int get hashCode => Object.hash(name, version);

  @override
  String toString() => '$name@$version';
}

/// Une bibliothèque telle que la liste une recherche : sa dernière version et de quoi la reconnaître.
class LibrarySummary {
  const LibrarySummary({
    required this.name,
    required this.latest,
    this.author = '',
    this.sentence = '',
    this.category = '',
    this.license,
    this.website,
    this.versionCount = 1,
  });

  final String name;

  /// Version la plus récente de l'index.
  final String latest;
  final String author;

  /// Description courte.
  final String sentence;
  final String category;

  /// Licence déclarée par la bibliothèque ; null si elle n'en précise pas.
  final String? license;
  final String? website;
  final int versionCount;

  Map<String, Object?> toJson() => {
        'name': name,
        'latest': latest,
        'author': author,
        'sentence': sentence,
        'category': category,
        if (license != null) 'license': license,
        if (website != null) 'website': website,
        'versionCount': versionCount,
      };

  factory LibrarySummary.fromJson(Map<String, Object?> json) => LibrarySummary(
        name: json['name'] as String,
        latest: json['latest'] as String,
        author: (json['author'] as String?) ?? '',
        sentence: (json['sentence'] as String?) ?? '',
        category: (json['category'] as String?) ?? '',
        license: json['license'] as String?,
        website: json['website'] as String?,
        versionCount: (json['versionCount'] as int?) ?? 1,
      );
}

/// Une version d'une bibliothèque, avec ce dont elle dépend.
class LibraryVersion {
  const LibraryVersion({required this.version, this.license, this.dependencies = const []});

  final String version;
  final String? license;

  /// Noms des bibliothèques dont cette version dépend.
  final List<String> dependencies;

  Map<String, Object?> toJson() => {
        'version': version,
        if (license != null) 'license': license,
        'dependencies': dependencies,
      };

  factory LibraryVersion.fromJson(Map<String, Object?> json) => LibraryVersion(
        version: json['version'] as String,
        license: json['license'] as String?,
        dependencies: [for (final d in (json['dependencies'] as List?) ?? const []) d as String],
      );
}

/// Réponse de `GET /v1/libraries/{name}` : la bibliothèque et toutes ses versions (la plus récente d'abord).
class LibraryDetail {
  const LibraryDetail({required this.summary, required this.versions, this.paragraph = ''});

  final LibrarySummary summary;
  final List<LibraryVersion> versions;

  /// Description longue.
  final String paragraph;

  Map<String, Object?> toJson() => {
        'summary': summary.toJson(),
        'paragraph': paragraph,
        'versions': [for (final v in versions) v.toJson()],
      };

  factory LibraryDetail.fromJson(Map<String, Object?> json) => LibraryDetail(
        summary: LibrarySummary.fromJson((json['summary'] as Map).cast()),
        paragraph: (json['paragraph'] as String?) ?? '',
        versions: [for (final v in (json['versions'] as List)) LibraryVersion.fromJson((v as Map).cast())],
      );
}

/// Réponse de `GET /v1/libraries/search`.
class LibrarySearchResult {
  const LibrarySearchResult({required this.total, required this.libraries});

  /// Nombre de bibliothèques qui correspondent (au-delà de celles renvoyées).
  final int total;
  final List<LibrarySummary> libraries;

  Map<String, Object?> toJson() => {'total': total, 'libraries': [for (final l in libraries) l.toJson()]};

  factory LibrarySearchResult.fromJson(Map<String, Object?> json) => LibrarySearchResult(
        total: json['total'] as int,
        libraries: [for (final l in (json['libraries'] as List)) LibrarySummary.fromJson((l as Map).cast())],
      );
}

/// Ce que dit le service d'un fichier d'en-tête (`#include <DHT.h>`).
class IncludeResolution {
  const IncludeResolution({
    required this.header,
    this.builtin = false,
    this.candidates = const [],
    this.confirmed = const [],
  });

  final String header;

  /// Fourni par le cœur de la carte (`Wire.h`, `SPI.h`…) : rien à ajouter.
  final bool builtin;

  /// Bibliothèques susceptibles de fournir cet en-tête, les plus probables d'abord.
  final List<LibrarySummary> candidates;

  /// Noms des candidats dont on a la certitude qu'ils fournissent l'en-tête : déclaré par l'index, ou trouvé en
  /// ouvrant la bibliothèque. L'index ne déclare presque jamais ses en-têtes, donc un candidat non confirmé est
  /// une simple suggestion (d'après son nom).
  final List<String> confirmed;

  Map<String, Object?> toJson() => {
        'header': header,
        'builtin': builtin,
        'candidates': [for (final c in candidates) c.toJson()],
        'confirmed': confirmed,
      };

  factory IncludeResolution.fromJson(Map<String, Object?> json) => IncludeResolution(
        header: json['header'] as String,
        builtin: (json['builtin'] as bool?) ?? false,
        candidates: [for (final c in (json['candidates'] as List?) ?? const []) LibrarySummary.fromJson((c as Map).cast())],
        confirmed: [for (final c in (json['confirmed'] as List?) ?? const []) c as String],
      );
}

/// Réponse de `POST /v1/libraries/closure` : les bibliothèques demandées avec leurs dépendances, chacune
/// à une version précise. C'est cette liste qu'un projet enregistre pour que ses compilations soient reproductibles.
class LibraryClosure {
  const LibraryClosure({required this.libraries});

  final List<LibraryRef> libraries;

  Map<String, Object?> toJson() => {'libraries': [for (final l in libraries) l.toJson()]};

  factory LibraryClosure.fromJson(Map<String, Object?> json) => LibraryClosure(
        libraries: [for (final l in (json['libraries'] as List)) LibraryRef.fromJson((l as Map).cast())],
      );
}
