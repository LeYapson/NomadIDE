import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nomad_compile_api/nomad_compile_api.dart';

/// Pourquoi un échange avec le service de compilation a échoué (le texte vient de la couche d'affichage).
enum CompileErrorKind {
  /// Adresse invalide, ou en clair vers un hôte public (le jeton ne doit pas circuler en clair).
  badUrl,
  unreachable,
  timeout,
  unauthorized,

  /// Le service refuse le projet (`detail` porte son explication).
  rejected,
  tooLarge,
  queueFull,

  /// Build inconnu : expiré (les résultats ne sont gardés que 30 minutes) ou jamais créé.
  notFound,
  badResponse,
}

class CompileApiException implements Exception {
  const CompileApiException(this.kind, {this.detail, this.cause});

  final CompileErrorKind kind;
  final String? detail;
  final Object? cause;

  @override
  String toString() => 'CompileApiException($kind${detail == null ? '' : ': $detail'})';
}

/// Ce que dit `GET /v1/health`.
class CompileServerInfo {
  const CompileServerInfo({required this.version, required this.boards, required this.maxUploadBytes});

  final String version;
  final List<CompileBoard> boards;
  final int maxUploadBytes;
}

/// Interface du service de compilation : remplacée par un faux dans les tests.
abstract class CompileApi {
  /// Joint le service (sans jeton) et lit ses limites.
  Future<CompileServerInfo> health();

  /// Vérifie que le jeton est accepté, sans lancer de compilation.
  Future<void> checkToken();

  Future<BuildStatus> submit(Uint8List zip, CompileBoard board, {String? sketch});

  Future<BuildStatus> status(String id);

  Future<Uint8List> downloadArtifact(String id, String name);

  /// Annule un build en cours ou supprime ses résultats. Les erreurs sont ignorées : sans effet pour l'utilisateur.
  Future<void> cancel(String id);
}

/// Adresse acceptée pour le service : HTTPS, ou HTTP vers cette machine / le réseau local seulement.
/// Le jeton est un mot de passe : il ne part jamais en clair sur internet.
bool isAcceptableServerUrl(String text) {
  final uri = Uri.tryParse(text.trim());
  if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return false;
  if (uri.scheme == 'https') return true;
  if (uri.scheme != 'http') return false;
  final host = uri.host.toLowerCase();
  if (host == 'localhost' || host.endsWith('.local')) return true;
  final address = InternetAddress.tryParse(host);
  return address != null && (address.isLoopback || address.isLinkLocal || _isPrivate(address));
}

bool _isPrivate(InternetAddress address) {
  if (address.type != InternetAddressType.IPv4) return address.rawAddress.first == 0xfd || address.rawAddress.first == 0xfc;
  final b = address.rawAddress;
  return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168);
}

class HttpCompileApi implements CompileApi {
  HttpCompileApi({
    required String baseUrl,
    required this.token,
    this.timeout = const Duration(seconds: 20),
    this.transferTimeout = const Duration(minutes: 2),
    this.maxArtifactBytes = 16 * 1024 * 1024,
  }) : _base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  final String _base;
  final String token;
  final Duration timeout;
  final Duration transferTimeout;
  final int maxArtifactBytes;

  @override
  Future<CompileServerInfo> health() async {
    final response = await _send('GET', '/v1/health', authorized: false);
    final json = _decodeJson(response);
    try {
      return CompileServerInfo(
        version: json['version'] as String,
        boards: [
          for (final b in (json['boards'] as List)) CompileBoard.fromId((b as Map)['id'] as String?),
        ].whereType<CompileBoard>().toList(),
        maxUploadBytes: json['maxUploadBytes'] as int,
      );
    } catch (e) {
      throw CompileApiException(CompileErrorKind.badResponse, cause: e);
    }
  }

  @override
  Future<void> checkToken() async {
    try {
      await _send('GET', '/v1/builds/jeton-test');
    } on CompileApiException catch (e) {
      // 404 : le jeton est accepté, c'est le build qui n'existe pas.
      if (e.kind != CompileErrorKind.notFound) rethrow;
    }
  }

  @override
  Future<BuildStatus> submit(Uint8List zip, CompileBoard board, {String? sketch}) async {
    final query = {'board': board.id, if (sketch != null) 'sketch': sketch};
    final response = await _send('POST', '/v1/builds', query: query, body: zip, contentType: 'application/zip');
    return _status(response);
  }

  @override
  Future<BuildStatus> status(String id) async => _status(await _send('GET', '/v1/builds/${Uri.encodeComponent(id)}'));

  @override
  Future<Uint8List> downloadArtifact(String id, String name) async {
    final response = await _send(
      'GET',
      '/v1/builds/${Uri.encodeComponent(id)}/artifacts/${Uri.encodeComponent(name)}',
      maxBytes: maxArtifactBytes,
    );
    return response.bytes;
  }

  @override
  Future<void> cancel(String id) async {
    try {
      await _send('DELETE', '/v1/builds/${Uri.encodeComponent(id)}');
    } on CompileApiException {
      // déjà parti ou injoignable : rien à faire de plus
    }
  }

  // ---------------------------------------------------------------------------

  BuildStatus _status(_Response response) {
    try {
      return BuildStatus.fromJson(_decodeJson(response));
    } on CompileApiException {
      rethrow;
    } catch (e) {
      throw CompileApiException(CompileErrorKind.badResponse, cause: e);
    }
  }

  Map<String, Object?> _decodeJson(_Response response) {
    try {
      final json = jsonDecode(utf8.decode(response.bytes));
      if (json is Map<String, Object?>) return json;
    } catch (_) {}
    throw const CompileApiException(CompileErrorKind.badResponse);
  }

  Future<_Response> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Uint8List? body,
    String? contentType,
    bool authorized = true,
    int maxBytes = 4 * 1024 * 1024,
  }) async {
    if (!isAcceptableServerUrl(_base)) throw const CompileApiException(CompileErrorKind.badUrl);
    final uri = Uri.parse('$_base$path').replace(queryParameters: query);
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.openUrl(method, uri).timeout(timeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'NomadIDE');
      if (authorized) request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (body != null) {
        request.headers.contentType = ContentType.parse(contentType ?? 'application/octet-stream');
        request.contentLength = body.length;
        request.add(body);
      }
      final response = await request.close().timeout(transferTimeout);
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(transferTimeout)) {
        bytes.add(chunk);
        if (bytes.length > maxBytes) throw const CompileApiException(CompileErrorKind.badResponse, detail: 'trop volumineux');
      }
      final result = _Response(response.statusCode, bytes.takeBytes());
      if (result.status >= 200 && result.status < 300) return result;
      throw _errorFor(result);
    } on CompileApiException {
      rethrow;
    } on TimeoutException catch (e) {
      throw CompileApiException(CompileErrorKind.timeout, cause: e);
    } on Object catch (e) {
      throw CompileApiException(CompileErrorKind.unreachable, cause: e);
    } finally {
      client.close(force: true);
    }
  }

  CompileApiException _errorFor(_Response response) {
    String? message;
    try {
      final json = jsonDecode(utf8.decode(response.bytes));
      if (json is Map) message = json['message'] as String?;
    } catch (_) {}
    return switch (response.status) {
      401 || 403 => const CompileApiException(CompileErrorKind.unauthorized),
      404 => const CompileApiException(CompileErrorKind.notFound),
      400 => CompileApiException(CompileErrorKind.rejected, detail: message),
      413 => CompileApiException(CompileErrorKind.tooLarge, detail: message),
      429 => CompileApiException(CompileErrorKind.queueFull, detail: message),
      _ => CompileApiException(CompileErrorKind.badResponse, detail: 'HTTP ${response.status}'),
    };
  }
}

class _Response {
  const _Response(this.status, this.bytes);

  final int status;
  final Uint8List bytes;
}
