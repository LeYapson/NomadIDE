import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'config.dart';
import 'job_manager.dart';
import 'libraries/library_service.dart';
import 'project_archive.dart';

const String serviceVersion = '0.1.0';

/// Construit le gestionnaire HTTP du service.
///
/// * `GET    /v1/health`                         sans jeton : état et cartes prises en charge
/// * `POST   /v1/builds?board=esp32[&sketch=x]`  corps `application/zip` : met un projet en file
/// * `GET    /v1/builds/{id}`                    état, journal, diagnostics, artefacts
/// * `GET    /v1/builds/{id}/artifacts/{name}`   télécharge un binaire
/// * `DELETE /v1/builds/{id}`                    annule (ou supprime) un build
/// * `GET    /v1/libraries/search?q=&board=`     cherche une bibliothèque Arduino
/// * `GET    /v1/libraries/{nom}`                versions, licences et dépendances d'une bibliothèque
/// * `POST   /v1/libraries/resolve`              quelles bibliothèques fournissent ces en-têtes (`#include`)
/// * `POST   /v1/libraries/closure`              bibliothèques demandées + dépendances, à des versions précises
Handler buildHandler({required ServerConfig config, required JobManager jobs, LibraryService? libraries}) {
  final router = Router()
    ..get('/v1/health', (Request request) => _json({
          'status': 'ok',
          'version': serviceVersion,
          'boards': [for (final b in CompileBoard.values) {'id': b.id, 'label': b.label}],
          'running': jobs.runningCount,
          'queued': jobs.queuedCount,
          'maxUploadBytes': config.maxUploadBytes,
          'libraries': {'available': libraries?.index != null, 'count': libraries?.index?.libraryCount ?? 0},
        }))
    ..get('/v1/libraries/search', (Request request) {
      final index = libraries?.index;
      if (index == null) return _libraryUnavailable();
      final params = request.url.queryParameters;
      final board = CompileBoard.fromId(params['board']);
      final limit = (int.tryParse(params['limit'] ?? '') ?? 20).clamp(1, 50);
      return _json(index.search(params['q'] ?? '', architecture: board?.architecture, limit: limit).toJson());
    })
    ..get('/v1/libraries/<name>', (Request request, String name) {
      final index = libraries?.index;
      if (index == null) return _libraryUnavailable();
      final detail = index.detail(Uri.decodeComponent(name));
      return detail == null ? _error(404, 'not_found', 'Bibliothèque inconnue : $name.') : _json(detail.toJson());
    })
    ..post('/v1/libraries/resolve', (Request request) async {
      final index = libraries?.index;
      if (index == null) return _libraryUnavailable();
      final body = await _readJson(request);
      final headers = body?['includes'];
      if (headers is! List || headers.length > 100 || headers.any((h) => h is! String)) {
        return _error(400, 'bad_request', 'Liste « includes » attendue (100 en-têtes au plus).');
      }
      final board = CompileBoard.fromId(body?['board'] as String?);
      final builtin = board == null ? null : libraries?.builtin.forFamily(board.family);
      final budget = VerifyBudget(8);
      final results = <IncludeResolution>[];
      for (final header in headers.cast<String>()) {
        if (builtin?.providesHeader(header) ?? false) {
          results.add(IncludeResolution(header: header, builtin: true));
          continue;
        }
        final resolved = await libraries!.resolveHeader(header, board: board, budget: budget);
        results.add(IncludeResolution(
          header: header,
          candidates: resolved.candidates,
          confirmed: [for (final c in resolved.candidates) if (resolved.confirmed.contains(c.name)) c.name],
        ));
      }
      return _json({'includes': [for (final r in results) r.toJson()]});
    })
    ..post('/v1/libraries/closure', (Request request) async {
      final index = libraries?.index;
      if (index == null) return _libraryUnavailable();
      final body = await _readJson(request);
      final list = body?['libraries'];
      if (list is! List || list.isEmpty || list.length > 40) {
        return _error(400, 'bad_request', 'Liste « libraries » attendue (1 à 40 bibliothèques).');
      }
      final requested = <LibraryRef>[];
      for (final item in list) {
        if (item is! Map || item['name'] is! String) return _error(400, 'bad_request', 'Chaque bibliothèque a un nom.');
        requested.add(LibraryRef(name: item['name'] as String, version: (item['version'] as String?) ?? ''));
      }
      final board = CompileBoard.fromId(body?['board'] as String?);
      final outcome = index.closure(
        requested,
        architecture: board?.architecture,
        builtin: board == null ? const {} : libraries!.builtin.forFamily(board.family).libraries,
      );
      if (!outcome.ok) return _error(400, 'unresolvable', outcome.problems.join(' '));
      return _json(LibraryClosure(libraries: [
        for (final r in outcome.releases) LibraryRef(name: r.name, version: r.version),
      ]).toJson());
    })
    ..post('/v1/builds', (Request request) async {
      final board = CompileBoard.fromId(request.url.queryParameters['board']);
      if (board == null) {
        return _error(400, 'unknown_board', 'Carte inconnue. Cartes disponibles : ${CompileBoard.values.map((b) => b.id).join(', ')}.');
      }
      final bytes = await _readLimited(request, config.maxUploadBytes);
      if (bytes == null) {
        return _error(413, 'too_large', 'Projet trop volumineux : ${config.maxUploadBytes ~/ (1024 * 1024)} Mo au maximum.');
      }
      try {
        final status = jobs.submit(board: board, zipBytes: bytes, sketchName: request.url.queryParameters['sketch']);
        return _json(status.toJson(), status: 202, headers: {'location': '/v1/builds/${status.id}'});
      } on ProjectException catch (e) {
        return _error(400, 'invalid_project', e.message);
      } on QueueFullException catch (e) {
        return _error(429, 'queue_full', "File d'attente pleine (${e.limit} compilations en attente). Réessayez dans un instant.",
            headers: {'retry-after': '30'});
      }
    })
    ..get('/v1/builds/<id>', (Request request, String id) {
      final status = jobs.status(id);
      return status == null ? _notFound() : _json(status.toJson());
    })
    ..get('/v1/builds/<id>/artifacts/<name>', (Request request, String id, String name) {
      final file = jobs.artifactFile(id, name);
      if (file == null || !file.existsSync()) return _notFound();
      return Response.ok(file.openRead(), headers: {
        'content-type': 'application/octet-stream',
        'content-length': '${file.lengthSync()}',
        'content-disposition': 'attachment; filename="${Uri.encodeComponent(name)}"',
      });
    })
    ..delete('/v1/builds/<id>', (Request request, String id) => jobs.cancel(id) ? Response(204) : _notFound());

  return const Pipeline()
      .addMiddleware(_securityHeaders())
      .addMiddleware(_bearerAuth(config.token, publicPaths: const {'v1/health'}))
      .addHandler(router.call);
}

/// Exige `Authorization: Bearer <jeton>` (comparaison en temps constant) sauf sur [publicPaths].
Middleware _bearerAuth(String token, {required Set<String> publicPaths}) {
  final expected = utf8.encode(token);
  return (inner) => (request) {
        if (publicPaths.contains(request.url.path)) return inner(request);
        final header = request.headers['authorization'] ?? '';
        final provided = header.startsWith('Bearer ') ? utf8.encode(header.substring(7).trim()) : const <int>[];
        if (!_constantTimeEquals(provided, expected)) {
          return _error(401, 'unauthorized', 'Jeton manquant ou invalide.', headers: {'www-authenticate': 'Bearer'});
        }
        return inner(request);
      };
}

Middleware _securityHeaders() => (inner) => (request) async {
      final response = await inner(request);
      return response.change(headers: {'cache-control': 'no-store', 'x-content-type-options': 'nosniff'});
    };

bool _constantTimeEquals(List<int> a, List<int> b) {
  var diff = a.length ^ b.length;
  final length = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Lit le corps de la requête, ou renvoie `null` dès qu'il dépasse [limit] octets.
Future<List<int>?> _readLimited(Request request, int limit) async {
  final declared = request.contentLength;
  if (declared != null && declared > limit) return null;
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in request.read()) {
    bytes.add(chunk);
    if (bytes.length > limit) return null;
  }
  return bytes.takeBytes();
}

Response _json(Object body, {int status = 200, Map<String, String> headers = const {}}) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json; charset=utf-8', ...headers},
    );

Response _error(int status, String code, String message, {Map<String, String> headers = const {}}) =>
    _json({'error': code, 'message': message}, status: status, headers: headers);

/// Corps JSON de la requête (64 Ko au plus), ou null s'il est absent ou invalide.
Future<Map<String, Object?>?> _readJson(Request request) async {
  final bytes = await _readLimited(request, 64 * 1024);
  if (bytes == null) return null;
  try {
    final json = jsonDecode(utf8.decode(bytes));
    return json is Map<String, Object?> ? json : null;
  } catch (_) {
    return null;
  }
}

Response _libraryUnavailable() => _error(
      503,
      'libraries_unavailable',
      "Le catalogue de bibliothèques n'est pas encore disponible : réessayez dans un instant.",
      headers: {'retry-after': '60'},
    );

Response _notFound() => _error(404, 'not_found', 'Introuvable (build expiré ou identifiant inconnu).');
