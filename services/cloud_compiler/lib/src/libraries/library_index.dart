import 'dart:convert';

import 'package:nomad_compile_api/nomad_compile_api.dart';

import 'arduino_version.dart';

class LibraryDependency {
  const LibraryDependency({required this.name, this.constraint});

  final String name;
  final String? constraint;
}

/// Une version d'une bibliothèque, telle que l'index officiel la décrit.
class LibraryRelease {
  LibraryRelease({
    required this.name,
    required this.version,
    required this.parsedVersion,
    required this.url,
    required this.size,
    required this.sha256,
    this.author = '',
    this.sentence = '',
    this.paragraph = '',
    this.category = '',
    this.website,
    this.license,
    this.architectures = const [],
    this.providesIncludes = const [],
    this.dependencies = const [],
  });

  final String name;
  final String version;
  final ArduinoVersion parsedVersion;
  final String author;
  final String sentence;
  final String paragraph;
  final String category;
  final String? website;
  final String? license;
  final List<String> architectures;
  final List<String> providesIncludes;
  final List<LibraryDependency> dependencies;

  /// Archive zip à télécharger, sa taille et son empreinte SHA-256 (hexadécimal, minuscules).
  final String url;
  final int size;
  final String sha256;

  /// Vrai si la bibliothèque convient à [architecture] (`esp32`, `rp2040`) : l'index déclare `*` ou la liste.
  bool supports(String? architecture) {
    if (architecture == null || architectures.isEmpty) return true;
    final wanted = architecture.toLowerCase();
    return architectures.any((a) => a == '*' || a.toLowerCase() == wanted);
  }
}

/// Le résultat de [LibraryIndex.closure].
class ClosureOutcome {
  const ClosureOutcome({this.releases = const [], this.problems = const []});

  /// Bibliothèques demandées et leurs dépendances, chacune à une version précise, dans l'ordre de choix.
  final List<LibraryRelease> releases;

  /// Explications (en français) de ce qui n'a pas pu être résolu ; vide si tout va bien.
  final List<String> problems;

  bool get ok => problems.isEmpty;
}

/// Catalogue des bibliothèques Arduino (le fichier `library_index.json` d'Arduino), interrogeable en mémoire.
class LibraryIndex {
  LibraryIndex._(this._releases, this._byLowerName, this._byInclude);

  final Map<String, List<LibraryRelease>> _releases;
  final Map<String, String> _byLowerName;
  final Map<String, Set<String>> _byInclude;

  int get libraryCount => _releases.length;

  /// Lit le JSON de l'index. Les entrées incomplètes (sans nom, version, adresse ou empreinte) sont ignorées ;
  /// les champs facultatifs absents ne gênent pas.
  factory LibraryIndex.parse(String jsonText) {
    final decoded = jsonDecode(jsonText);
    final list = decoded is Map ? decoded['libraries'] : null;
    if (list is! List) throw const FormatException("Index de bibliothèques illisible : champ « libraries » absent.");

    final releases = <String, List<LibraryRelease>>{};
    for (final entry in list) {
      if (entry is! Map) continue;
      final release = _parseRelease(entry);
      if (release != null) releases.putIfAbsent(release.name, () => []).add(release);
    }
    final byLower = <String, String>{};
    final byInclude = <String, Set<String>>{};
    for (final entry in releases.entries) {
      entry.value.sort((a, b) => a.parsedVersion.compareTo(b.parsedVersion));
      byLower[entry.key.toLowerCase()] = entry.key;
      // Les en-têtes d'une bibliothèque sont ceux de ses versions : une version récente peut en avoir ajouté.
      for (final release in entry.value) {
        for (final header in release.providesIncludes) {
          byInclude.putIfAbsent(header, () => {}).add(entry.key);
        }
      }
    }
    return LibraryIndex._(releases, byLower, byInclude);
  }

  static LibraryRelease? _parseRelease(Map entry) {
    final name = entry['name'];
    final version = entry['version'];
    final url = entry['url'];
    final checksum = entry['checksum'];
    if (name is! String || version is! String || url is! String || checksum is! String) return null;
    final parsed = ArduinoVersion.tryParse(version);
    if (parsed == null) return null;
    final hash = checksum.contains(':') ? checksum.substring(checksum.indexOf(':') + 1) : checksum;
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hash)) return null;

    List<String> strings(Object? value) => [for (final v in (value is List ? value : const [])) if (v is String) v];
    final includes = entry['providesIncludes'] ?? entry['provides_includes'];
    final dependencies = <LibraryDependency>[];
    final rawDependencies = entry['dependencies'];
    if (rawDependencies is List) {
      for (final d in rawDependencies) {
        if (d is Map && d['name'] is String) {
          final constraint = d['version'];
          dependencies.add(LibraryDependency(name: d['name'] as String, constraint: constraint is String ? constraint : null));
        }
      }
    }
    final license = entry['license'];
    final website = entry['website'];
    return LibraryRelease(
      name: name,
      version: version,
      parsedVersion: parsed,
      url: url,
      size: entry['size'] is int ? entry['size'] as int : 0,
      sha256: hash.toLowerCase(),
      author: entry['author'] is String ? entry['author'] as String : '',
      sentence: entry['sentence'] is String ? entry['sentence'] as String : '',
      paragraph: entry['paragraph'] is String ? entry['paragraph'] as String : '',
      category: entry['category'] is String ? entry['category'] as String : '',
      website: website is String && website.isNotEmpty ? website : null,
      license: license is String && license.trim().isNotEmpty ? license.trim() : null,
      architectures: strings(entry['architectures']),
      providesIncludes: strings(includes),
      dependencies: dependencies,
    );
  }

  /// Nom exact de l'index pour [name] (insensible à la casse), ou null.
  String? canonicalName(String name) => _releases.containsKey(name) ? name : _byLowerName[name.toLowerCase()];

  /// Versions de [name], de la plus ancienne à la plus récente.
  List<LibraryRelease> releases(String name) => _releases[canonicalName(name) ?? name] ?? const [];

  LibraryRelease? latest(String name, {String? architecture}) {
    final all = releases(name);
    for (var i = all.length - 1; i >= 0; i--) {
      if (all[i].parsedVersion.pre.isEmpty && all[i].supports(architecture)) return all[i];
    }
    return all.isEmpty ? null : all.last;
  }

  LibraryRelease? release(String name, String version) {
    final wanted = ArduinoVersion.tryParse(version);
    for (final r in releases(name)) {
      if (r.version == version || (wanted != null && r.parsedVersion == wanted)) return r;
    }
    return null;
  }

  LibrarySummary summary(String name) {
    final canonical = canonicalName(name)!;
    final all = _releases[canonical]!;
    final latest = this.latest(canonical)!;
    return LibrarySummary(
      name: canonical,
      latest: latest.version,
      author: latest.author,
      sentence: latest.sentence,
      category: latest.category,
      license: latest.license,
      website: latest.website,
      versionCount: all.length,
    );
  }

  LibraryDetail? detail(String name) {
    final canonical = canonicalName(name);
    if (canonical == null) return null;
    final all = _releases[canonical]!;
    return LibraryDetail(
      summary: summary(canonical),
      paragraph: latest(canonical)!.paragraph,
      versions: [
        for (final r in all.reversed)
          LibraryVersion(version: r.version, license: r.license, dependencies: [for (final d in r.dependencies) d.name]),
      ],
    );
  }

  /// Recherche par mots : chaque mot doit se retrouver quelque part (nom, auteur, catégorie, descriptions).
  /// Le nom pèse le plus ; à score égal, la bibliothèque qui a le plus de versions (donc la plus suivie) passe d'abord.
  LibrarySearchResult search(String query, {String? architecture, int limit = 20}) {
    final tokens = query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return const LibrarySearchResult(total: 0, libraries: []);

    final scored = <(String, int)>[];
    for (final entry in _releases.entries) {
      final latest = this.latest(entry.key, architecture: architecture);
      if (latest == null || !latest.supports(architecture)) continue;
      final name = entry.key.toLowerCase();
      final nameWords = name.split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty).toSet();
      final author = latest.author.toLowerCase();
      final category = latest.category.toLowerCase();
      final sentence = latest.sentence.toLowerCase();
      final paragraph = latest.paragraph.toLowerCase();
      var total = 0;
      var matchedAll = true;
      for (final token in tokens) {
        var score = 0;
        if (name == token) {
          score = 100;
        } else if (nameWords.contains(token)) {
          score = 75; // « DHT » est un mot du nom : mieux que le début d'un nom collé (« DHTNEW »)
        } else if (name.startsWith(token)) {
          score = 60;
        } else if (name.contains(token)) {
          score = 40;
        } else if (author.contains(token)) {
          score = 15;
        } else if (category.contains(token)) {
          score = 10;
        } else if (sentence.contains(token)) {
          score = 8;
        } else if (paragraph.contains(token)) {
          score = 4;
        }
        if (score == 0) {
          matchedAll = false;
          break;
        }
        total += score;
      }
      if (matchedAll) scored.add((entry.key, total));
    }
    scored.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      if (byScore != 0) return byScore;
      final byTrust = trustRank(b.$1).compareTo(trustRank(a.$1));
      if (byTrust != 0) return byTrust;
      final byVersions = _releases[b.$1]!.length.compareTo(_releases[a.$1]!.length);
      return byVersions != 0 ? byVersions : a.$1.compareTo(b.$1);
    });
    return LibrarySearchResult(
      total: scored.length,
      libraries: [for (final s in scored.take(limit)) summary(s.$1)],
    );
  }

  /// Bibliothèques de l'index qui fournissent [header] (`DHT.h`), les plus probables d'abord : celle dont
  /// le nom est celui de l'en-tête, puis les plus suivies.
  List<LibrarySummary> providersOf(String header, {String? architecture}) {
    final names = _byInclude[header] ?? _byInclude[_byInclude.keys.firstWhere((k) => k.toLowerCase() == header.toLowerCase(), orElse: () => '')];
    if (names == null) return const [];
    final base = header.replaceAll(RegExp(r'\.(h|hpp)$', caseSensitive: false), '').toLowerCase();
    final candidates = [
      for (final name in names)
        if (latest(name, architecture: architecture)?.supports(architecture) ?? false) name,
    ];
    candidates.sort((a, b) {
      final exactA = a.toLowerCase() == base ? 0 : 1;
      final exactB = b.toLowerCase() == base ? 0 : 1;
      if (exactA != exactB) return exactA.compareTo(exactB);
      final byTrust = trustRank(b).compareTo(trustRank(a));
      if (byTrust != 0) return byTrust;
      final byVersions = _releases[b]!.length.compareTo(_releases[a]!.length);
      return byVersions != 0 ? byVersions : a.compareTo(b);
    });
    return [for (final name in candidates) summary(name)];
  }

  /// L'index ne dit rien de la popularité : à défaut, on donne la priorité aux éditeurs dont les bibliothèques
  /// sont celles des tutoriels et des cartes (Adafruit, Arduino, SparkFun, Espressif…). 1 si l'auteur en fait
  /// partie, 0 sinon. Ce n'est qu'un départage : l'utilisateur voit les autres candidats.
  int trustRank(String name) {
    final author = latest(name)?.author.toLowerCase() ?? '';
    return RegExp(r'adafruit|arduino|sparkfun|espressif|earlephilhower|seeed|pimoroni').hasMatch(author) ? 1 : 0;
  }

  /// Bibliothèques dont le nom ressemble à [header] (`Adafruit_SSD1306.h` : « Adafruit SSD1306 »). L'index ne déclare
  /// presque jamais les en-têtes que fournit une bibliothèque : le nom est le seul indice avant d'ouvrir l'archive.
  /// Noms comparés sans casse ni séparateurs ; égalité d'abord, puis début de nom, puis nom contenu dans l'en-tête.
  List<LibrarySummary> nameCandidates(String header, {String? architecture, int limit = 8}) {
    final scored = <(String, int)>[];
    for (final name in _releases.keys) {
      final score = nameScore(header, name);
      if (score == 0) continue;
      final latest = this.latest(name, architecture: architecture);
      if (latest == null || !latest.supports(architecture)) continue;
      scored.add((name, score));
    }
    scored.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      if (byScore != 0) return byScore;
      final byTrust = trustRank(b.$1).compareTo(trustRank(a.$1));
      if (byTrust != 0) return byTrust;
      final byVersions = _releases[b.$1]!.length.compareTo(_releases[a.$1]!.length);
      if (byVersions != 0) return byVersions;
      final byLength = a.$1.length.compareTo(b.$1.length);
      return byLength != 0 ? byLength : a.$1.compareTo(b.$1);
    });
    return [for (final s in scored.take(limit)) summary(s.$1)];
  }

  /// À quel point le nom de [name] ressemble à [header] : 100 pour le même nom (sans casse ni séparateurs), 70 si le
  /// nom commence par l'en-tête, 50 si l'en-tête commence par le nom, 40 si le nom le contient, 0 sinon.
  int nameScore(String header, String name) {
    final base = _normalize(header.replaceAll(RegExp(r'\.(h|hpp|hh)$', caseSensitive: false), ''));
    if (base.length < 3) return 0;
    final n = _normalize(name);
    if (n == base) return 100;
    if (n.startsWith(base)) return 70;
    if (n.length >= 4 && base.startsWith(n)) return 50;
    if (base.length >= 4 && n.contains(base)) return 40;
    return 0;
  }

  static String _normalize(String text) => text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Résout [requested] (nom et version facultative) avec toutes les dépendances, chacune à une version précise.
  /// Sans version demandée : la dernière. Une dépendance garde la dernière version qui respecte sa contrainte ;
  /// deux contraintes incompatibles sur une même bibliothèque sont signalées plutôt que tranchées en silence.
  /// [builtin] : noms de bibliothèques déjà fournies par le cœur de la carte (`Wire`, `SPI`…), jamais cherchées.
  ClosureOutcome closure(List<LibraryRef> requested, {String? architecture, Set<String> builtin = const {}}) {
    final chosen = <String, LibraryRelease>{};
    final constraints = <String, List<String>>{};
    final problems = <String>[];
    final builtinLower = {for (final b in builtin) b.toLowerCase()};

    void add(String name, String? constraint, {required bool explicit, String? requestedBy}) {
      final canonical = canonicalName(name);
      if (canonical == null) {
        if (!builtinLower.contains(name.toLowerCase())) {
          problems.add(requestedBy == null
              ? 'Bibliothèque inconnue : $name.'
              : 'Bibliothèque inconnue : $name (nécessaire à $requestedBy).');
        }
        return;
      }
      if (constraint != null) constraints.putIfAbsent(canonical, () => []).add(constraint);
      final existing = chosen[canonical];
      if (existing != null) {
        if (constraint != null && !satisfies(existing.parsedVersion, constraint)) {
          problems.add('$canonical ${existing.version} ne respecte pas « $constraint »'
              '${requestedBy == null ? '' : ' (demandé par $requestedBy)'}.');
        }
        return;
      }
      LibraryRelease? pick;
      if (explicit && constraint != null) {
        pick = release(canonical, constraint);
        if (pick == null) {
          problems.add('Version inconnue : $canonical $constraint.');
          return;
        }
      } else {
        final all = releases(canonical);
        for (var i = all.length - 1; i >= 0; i--) {
          final candidate = all[i];
          if (!satisfies(candidate.parsedVersion, constraint)) continue;
          if (candidate.parsedVersion.pre.isEmpty) {
            pick = candidate;
            break;
          }
          pick ??= candidate; // une préversion ne sert qu'à défaut de version finale
        }
        if (pick == null) {
          problems.add('Aucune version de $canonical ne respecte « $constraint »'
              '${requestedBy == null ? '' : ' (nécessaire à $requestedBy)'}.');
          return;
        }
      }
      chosen[canonical] = pick;
      for (final dep in pick.dependencies) {
        add(dep.name, dep.constraint, explicit: false, requestedBy: canonical);
      }
    }

    for (final ref in requested) {
      add(ref.name, ref.version.isEmpty ? null : ref.version, explicit: true);
    }
    // Une contrainte ajoutée après le choix d'une version : on revérifie les versions retenues.
    for (final entry in constraints.entries) {
      final release = chosen[entry.key];
      if (release == null) continue;
      for (final c in entry.value) {
        if (!satisfies(release.parsedVersion, c) && !problems.any((p) => p.contains('« $c »') && p.contains(entry.key))) {
          problems.add('${entry.key} ${release.version} ne respecte pas « $c ».');
        }
      }
    }
    if (architecture != null) {
      for (final release in chosen.values) {
        if (!release.supports(architecture)) {
          problems.add('${release.name} ne prend pas en charge l\'architecture $architecture.');
        }
      }
    }
    return ClosureOutcome(releases: chosen.values.toList(), problems: problems);
  }
}
