import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nomad_compile_api/nomad_compile_api.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'config.dart';
import 'job_manager.dart';
import 'project_archive.dart';

const String serviceVersion = '0.1.0';

/// Construit le gestionnaire HTTP du service.
///
/// * `GET    /v1/health`                         sans jeton : état et cartes prises en charge
/// * `POST   /v1/builds?board=esp32[&sketch=x]`  corps `application/zip` : met un projet en file
/// * `GET    /v1/builds/{id}`                    état, journal, diagnostics, artefacts
/// * `GET    /v1/builds/{id}/artifacts/{name}`   télécharge un binaire
/// * `DELETE /v1/builds/{id}`                    annule (ou supprime) un build
Handler buildHandler({required ServerConfig config, required JobManager jobs}) {
  final router = Router()
    ..get('/v1/health', (Request request) => _json({
          'status': 'ok',
          'version': serviceVersion,
          'boards': [for (final b in CompileBoard.values) {'id': b.id, 'label': b.label}],
          'running': jobs.runningCount,
          'queued': jobs.queuedCount,
          'maxUploadBytes': config.maxUploadBytes,
        }))
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

Response _notFound() => _error(404, 'not_found', 'Introuvable (build expiré ou identifiant inconnu).');
