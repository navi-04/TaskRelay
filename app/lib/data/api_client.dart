import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_exception.dart';

/// A small JSON client for `/api/v1`. Sends the session token and app version, maps every failure to an [ApiException],
/// and retries once when it is safe to (reads, and writes the server treats as idempotent).
class ApiClient {
  ApiClient({
    http.Client? client,
    required this.baseUrl,
    required this.token,
    required this.appVersion,
    this.onUnauthorized,
    this.onUpgradeRequired,
    this.timeout = const Duration(seconds: 15),
  }) : _http = client ?? http.Client();

  final http.Client _http;
  final String baseUrl;
  final String? Function() token;
  final String Function() appVersion;

  /// Called when a request that carried a session gets a 401 (the session expired or was revoked).
  final void Function()? onUnauthorized;

  /// Called when the server says this app version is too old (HTTP 426).
  final void Function()? onUpgradeRequired;
  final Duration timeout;

  Future<dynamic> get(String path, {Map<String, String>? query}) => _send('GET', path, query: query, retry: true);

  /// [idempotent]: safe to repeat (e.g. creating a task with a client-chosen id).
  Future<dynamic> post(String path, {Object? body, bool idempotent = false}) => _send('POST', path, body: body, retry: idempotent);

  Future<dynamic> put(String path, {Object? body}) => _send('PUT', path, body: body, retry: true);

  Future<dynamic> patch(String path, {Object? body}) => _send('PATCH', path, body: body);

  Future<dynamic> delete(String path, {Map<String, String>? query, Object? body}) => _send('DELETE', path, query: query, body: body);

  /// The raw bytes of a download (used by data export).
  Future<List<int>> download(String path) async {
    final res = await _request('GET', path, null, null);
    return res.bodyBytes;
  }

  Future<dynamic> _send(String method, String path, {Map<String, String>? query, Object? body, bool retry = false}) async {
    try {
      return _decode(await _request(method, path, query, body), path);
    } on ApiException catch (e) {
      if (retry && e.isOffline) return _decode(await _request(method, path, query, body), path); // one more try on a flaky connection
      rethrow;
    }
  }

  Future<http.Response> _request(String method, String path, Map<String, String>? query, Object? body) async {
    final uri = Uri.parse('$baseUrl/api/v1$path').replace(queryParameters: query == null || query.isEmpty ? null : query);
    final req = http.Request(method, uri)
      ..headers['Accept'] = 'application/json'
      ..headers['X-App-Version'] = appVersion();
    final t = token();
    if (t != null) req.headers['Authorization'] = 'Bearer $t';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    try {
      final streamed = await _http.send(req).timeout(timeout);
      return await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw const ApiException(ApiErrorKind.timeout, 'The server took too long to answer.');
    } on SocketException {
      throw const ApiException(ApiErrorKind.network, 'No connection.');
    } on HandshakeException {
      throw const ApiException(ApiErrorKind.network, 'Secure connection failed.');
    } on http.ClientException {
      throw const ApiException(ApiErrorKind.network, 'No connection.');
    }
  }

  dynamic _decode(http.Response res, String path) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      try {
        return jsonDecode(utf8.decode(res.bodyBytes));
      } on FormatException {
        throw ApiException(ApiErrorKind.server, 'The server sent something unexpected.', status: res.statusCode);
      }
    }

    String message = res.reasonPhrase ?? 'Request failed';
    String? code;
    var issues = const <FieldIssue>[];
    try {
      final err = (jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)['error'] as Map<String, dynamic>?;
      if (err != null) {
        message = (err['message'] as String?) ?? message;
        code = err['code'] as String?;
        issues = ((err['issues'] as List?) ?? const []).map((i) => FieldIssue((i['path'] ?? '').toString(), (i['message'] ?? '').toString())).toList();
      }
    } catch (_) {
      // not JSON (e.g. a gateway error page): keep the generic message
    }

    final status = res.statusCode;
    final retryAfter = int.tryParse(res.headers['retry-after'] ?? '');
    ApiErrorKind kind;
    if (status == 401) {
      kind = ApiErrorKind.unauthorized;
      // Wrong email/password on the sign-in form is a 401 too, but it is not an expired session.
      if (!path.startsWith('/auth/')) onUnauthorized?.call();
    } else if (status == 426) {
      kind = ApiErrorKind.upgradeRequired;
      onUpgradeRequired?.call();
    } else if (status == 429) {
      kind = ApiErrorKind.rateLimited;
    } else if (status == 403) {
      kind = ApiErrorKind.forbidden;
    } else if (status == 404) {
      kind = ApiErrorKind.notFound;
    } else if (status == 409) {
      kind = ApiErrorKind.conflict;
    } else if (status == 400 || status == 422) {
      kind = ApiErrorKind.validation;
    } else if (status >= 500) {
      kind = ApiErrorKind.server;
    } else {
      kind = ApiErrorKind.unknown;
    }
    throw ApiException(kind, message, code: code, status: status, retryAfter: retryAfter == null ? null : Duration(seconds: retryAfter), issues: issues);
  }

  void close() => _http.close();
}
