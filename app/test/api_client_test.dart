import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taskrelay/data/api_client.dart';
import 'package:taskrelay/data/api_exception.dart';

ApiClient clientFor(MockClient mock, {String? token = 'tok', void Function()? onUnauthorized, void Function()? onUpgrade, Duration? timeout}) => ApiClient(
      client: mock,
      baseUrl: 'https://api.test',
      token: () => token,
      appVersion: () => '2.0.0',
      onUnauthorized: onUnauthorized,
      onUpgradeRequired: onUpgrade,
      timeout: timeout ?? const Duration(seconds: 2),
    );

http.Response json(String body, [int status = 200, Map<String, String>? headers]) => http.Response(body, status, headers: {'content-type': 'application/json', ...?headers});

Future<ApiException> failure(Future<dynamic> f) async {
  try {
    await f;
  } on ApiException catch (e) {
    return e;
  }
  fail('expected an ApiException');
}

void main() {
  test('sends the session token and app version, and decodes JSON', () async {
    late http.Request seen;
    final c = clientFor(MockClient((r) async {
      seen = r;
      return json('{"ok":true}');
    }));
    expect(await c.get('/tasks', query: {'date': '2026-11-06'}), {'ok': true});
    expect(seen.url.toString(), 'https://api.test/api/v1/tasks?date=2026-11-06');
    expect(seen.headers['Authorization'], 'Bearer tok');
    expect(seen.headers['X-App-Version'], '2.0.0');
  });

  test('sends no Authorization header when signed out, and a JSON body with the right content type', () async {
    late http.Request seen;
    final c = clientFor(MockClient((r) async {
      seen = r;
      return json('{}');
    }), token: null);
    await c.post('/auth/login', body: {'email': 'a@b.c', 'password': 'x'});
    expect(seen.headers.containsKey('Authorization'), isFalse);
    expect(seen.headers['Content-Type'], contains('application/json'));
    expect(seen.body, '{"email":"a@b.c","password":"x"}');
  });

  group('error mapping', () {
    test('401 on a normal call signs the session out (once) and is reported as unauthorized', () async {
      var expired = 0;
      final c = clientFor(MockClient((_) async => json('{"error":{"code":"unauthorized","message":"Not signed in"}}', 401)), onUnauthorized: () => expired++);
      final e = await failure(c.get('/tasks'));
      expect([e.kind, expired], [ApiErrorKind.unauthorized, 1]);
    });

    test('401 on the sign-in form is a wrong password, not an expired session', () async {
      var expired = 0;
      final c = clientFor(MockClient((_) async => json('{"error":{"code":"invalid_credentials","message":"Wrong email or password"}}', 401)), onUnauthorized: () => expired++);
      final e = await failure(c.post('/auth/login', body: {}));
      expect([e.kind, e.message, expired], [ApiErrorKind.unauthorized, 'Wrong email or password', 0]);
    });

    test('426 asks the app to update', () async {
      var upgrades = 0;
      final c = clientFor(MockClient((_) async => json('{"error":{"code":"upgrade_required","message":"Please update"}}', 426)), onUpgrade: () => upgrades++);
      expect((await failure(c.get('/tasks'))).kind, ApiErrorKind.upgradeRequired);
      expect(upgrades, 1);
    });

    test('429 carries Retry-After', () async {
      final c = clientFor(MockClient((_) async => json('{"error":{"code":"rate_limited","message":"Slow down"}}', 429, {'retry-after': '42'})));
      final e = await failure(c.post('/tasks'));
      expect([e.kind, e.retryAfter], [ApiErrorKind.rateLimited, const Duration(seconds: 42)]);
      expect(friendlyError(e), contains('42'));
    });

    test('400 validation errors expose the per-field issues', () async {
      final c = clientFor(MockClient((_) async => json('{"error":{"code":"validation_error","message":"bad","issues":[{"path":"title","message":"Too short"},{"path":"duration_min","message":"Too big"}]}}', 400)));
      final e = await failure(c.post('/tasks'));
      expect(e.kind, ApiErrorKind.validation);
      expect(e.issues.map((i) => '${i.path}: ${i.message}'), ['title: Too short', 'duration_min: Too big']);
    });

    test('404, 409, 403 and 5xx map to their kinds, keeping the server code', () async {
      Future<ApiException> status(int s, String code) => failure(clientFor(MockClient((_) async => json('{"error":{"code":"$code","message":"m"}}', s))).get('/x'));
      expect((await status(404, 'not_found')).kind, ApiErrorKind.notFound);
      expect((await status(409, 'id_in_use')).code, 'id_in_use');
      expect((await status(403, 'wrong_password')).kind, ApiErrorKind.forbidden);
      expect((await status(503, 'x')).kind, ApiErrorKind.server);
    });

    test('a non-JSON error page (a gateway) still becomes a clean server error', () async {
      final c = clientFor(MockClient((_) async => http.Response('<html>Bad gateway</html>', 502)));
      expect((await failure(c.get('/tasks'))).kind, ApiErrorKind.server);
    });
  });

  group('connectivity', () {
    test('no connection -> network; reads retry once and succeed on the second try', () async {
      var calls = 0;
      final c = clientFor(MockClient((_) async {
        if (++calls == 1) throw const SocketException('offline');
        return json('{"ok":1}');
      }));
      expect(await c.get('/tasks'), {'ok': 1});
      expect(calls, 2);
    });

    test('a write that is not safe to repeat is NOT retried', () async {
      var calls = 0;
      final c = clientFor(MockClient((_) async {
        calls++;
        throw const SocketException('offline');
      }));
      final e = await failure(c.patch('/tasks/x', body: {'title': 'a'}));
      expect([e.kind, e.isOffline, calls], [ApiErrorKind.network, true, 1]);
    });

    test('an idempotent create (client-chosen id) IS retried', () async {
      var calls = 0;
      final c = clientFor(MockClient((_) async {
        if (++calls == 1) throw const SocketException('offline');
        return json('{"id":"abc"}', 201);
      }));
      expect(await c.post('/tasks', body: {'id': 'abc'}, idempotent: true), {'id': 'abc'});
      expect(calls, 2);
    });

    test('a slow server times out', () async {
      final c = clientFor(MockClient((_) => Completer<http.Response>().future), timeout: const Duration(milliseconds: 50));
      final e = await failure(c.post('/tasks'));
      expect(e.kind, ApiErrorKind.timeout);
      expect(e.isOffline, isTrue);
    });
  });

  test('friendlyError never leaks internals for unknown errors', () {
    expect(friendlyError(StateError('boom')), isNot(contains('boom')));
    expect(friendlyError(const ApiException(ApiErrorKind.network, 'x')), contains('connection'));
  });
}
