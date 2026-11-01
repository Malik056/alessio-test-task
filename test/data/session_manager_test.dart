import 'dart:async';
import 'dart:convert';

import 'package:dummy_shop/core/api_client.dart';
import 'package:dummy_shop/data/models/auth_tokens.dart';
import 'package:dummy_shop/data/services/session_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/fixtures.dart';

void main() {
  final valid = jwt(const Duration(hours: 1), id: 'valid');
  final expired = jwt(const Duration(minutes: -5), id: 'expired');
  final refreshValid = jwt(const Duration(days: 30), id: 'refresh');
  final refreshExpired = jwt(const Duration(days: -1), id: 'refresh-old');
  final newAccess = jwt(const Duration(hours: 1), id: 'new');
  final newRefresh = jwt(const Duration(days: 30), id: 'new-refresh');

  late InMemoryTokenStorage storage;
  late List<http.Request> requests;
  late FutureOr<http.Response> Function(http.Request) respond;
  late SessionManager session;

  http.Response refreshed() => http.Response(
    jsonEncode({'accessToken': newAccess, 'refreshToken': newRefresh}),
    200,
  );

  setUp(() {
    storage = InMemoryTokenStorage();
    requests = [];
    respond = (_) => refreshed();
    session = SessionManager(
      storage: storage,
      authApi: ApiClient(
        httpClient: MockClient((request) async {
          requests.add(request);
          return respond(request);
        }),
        baseUrl: 'https://api.test',
      ),
    );
  });

  group('restore (app start)', () {
    test('no stored tokens → logged out', () async {
      expect(await session.restore(), isFalse);
      expect(requests, isEmpty);
    });

    test('valid access token → logged in without a network call', () async {
      storage.tokens = AuthTokens(
        accessToken: valid,
        refreshToken: refreshValid,
      );

      expect(await session.restore(), isTrue);
      expect(requests, isEmpty);
    });

    test('expired access token → refreshes and stores the new pair', () async {
      storage.tokens = AuthTokens(
        accessToken: expired,
        refreshToken: refreshValid,
      );

      expect(await session.restore(), isTrue);

      expect(requests.single.url.path, '/auth/refresh');
      expect(jsonDecode(requests.single.body), {'refreshToken': refreshValid});
      expect(storage.tokens?.accessToken, newAccess);
      expect(storage.tokens?.refreshToken, newRefresh);
    });

    test('token about to expire (within leeway) is refreshed', () async {
      storage.tokens = AuthTokens(
        accessToken: jwt(const Duration(seconds: 10)),
        refreshToken: refreshValid,
      );

      await session.restore();

      expect(requests, hasLength(1));
    });

    test('both tokens expired → logged out without a network call', () async {
      storage.tokens = AuthTokens(
        accessToken: expired,
        refreshToken: refreshExpired,
      );

      expect(await session.restore(), isFalse);
      expect(requests, isEmpty);
      expect(storage.tokens, isNull);
    });

    test('refresh rejected → logged out', () async {
      storage.tokens = AuthTokens(
        accessToken: expired,
        refreshToken: refreshValid,
      );
      respond = (_) =>
          http.Response('{"message":"Invalid refresh token"}', 403);

      expect(await session.restore(), isFalse);
      expect(storage.tokens, isNull);
    });

    test('offline → keeps the session to retry later', () async {
      final tokens = AuthTokens(
        accessToken: expired,
        refreshToken: refreshValid,
      );
      storage.tokens = tokens;
      respond = (_) => throw http.ClientException('offline');

      expect(await session.restore(), isTrue);
      expect(storage.tokens, same(tokens));
    });

    test(
      'opaque (non-JWT) token → trusted until the server says 401',
      () async {
        storage.tokens = const AuthTokens(
          accessToken: 'opaque',
          refreshToken: 'r',
        );

        expect(await session.restore(), isTrue);
        expect(requests, isEmpty);
      },
    );
  });

  group('refreshAccessToken (after a 401)', () {
    setUp(() {
      storage.tokens = AuthTokens(
        accessToken: expired,
        refreshToken: refreshValid,
      );
    });

    test('returns and stores the new access token', () async {
      expect(await session.refreshAccessToken(failedToken: expired), newAccess);
      expect(storage.tokens?.refreshToken, newRefresh);
    });

    test('concurrent 401s share a single refresh call', () async {
      final gate = Completer<void>();
      respond = (_) async {
        await gate.future;
        return refreshed();
      };

      final results = Future.wait([
        session.refreshAccessToken(failedToken: expired),
        session.refreshAccessToken(failedToken: expired),
        session.refreshAccessToken(failedToken: expired),
      ]);
      await pumpEventQueue();
      gate.complete();

      expect(await results, [newAccess, newAccess, newAccess]);
      expect(requests, hasLength(1));
    });

    test(
      'a 401 for an already-replaced token reuses the current one',
      () async {
        await session.refreshAccessToken(failedToken: expired);
        requests.clear();

        // A request sent with the old token comes back after the refresh.
        expect(
          await session.refreshAccessToken(failedToken: expired),
          newAccess,
        );
        expect(requests, isEmpty);
      },
    );

    test('rejected refresh returns null and clears tokens', () async {
      respond = (_) =>
          http.Response('{"message":"Invalid refresh token"}', 403);

      expect(await session.refreshAccessToken(failedToken: expired), isNull);
      expect(storage.tokens, isNull);
    });

    test('network error propagates and keeps the session', () async {
      respond = (_) => throw http.ClientException('offline');

      await expectLater(
        session.refreshAccessToken(failedToken: expired),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('internet'),
          ),
        ),
      );
      expect(storage.tokens, isNotNull);
    });

    test('server error (5xx) keeps the session', () async {
      respond = (_) => http.Response('{"message":"down"}', 503);

      await expectLater(
        session.refreshAccessToken(failedToken: expired),
        throwsA(isA<Exception>()),
      );
      expect(storage.tokens, isNotNull);
    });

    test('no session → null without a network call', () async {
      storage.tokens = null;

      expect(await session.refreshAccessToken(failedToken: expired), isNull);
      expect(requests, isEmpty);
    });
  });

  group('login/logout while a refresh is in flight', () {
    late Completer<void> gate;

    setUp(() {
      storage.tokens = AuthTokens(
        accessToken: expired,
        refreshToken: refreshValid,
      );
      gate = Completer<void>();
      respond = (_) async {
        await gate.future;
        return refreshed();
      };
    });

    test(
      'logout wins: the late refresh does not restore the session',
      () async {
        final refresh = session.refreshAccessToken(failedToken: expired);
        await pumpEventQueue(); // refresh request is now on the wire
        final logout = session.end();

        gate.complete(); // refresh response arrives after the logout tap
        await Future.wait([refresh, logout]);

        expect(storage.tokens, isNull);
        expect(await session.restore(), isFalse);
      },
    );

    test('logout waits for the in-flight refresh before clearing', () async {
      session.refreshAccessToken(failedToken: expired);
      await pumpEventQueue();
      var loggedOut = false;
      session.end().then((_) => loggedOut = true);

      await pumpEventQueue();
      expect(loggedOut, isFalse);

      gate.complete();
      await pumpEventQueue();
      expect(loggedOut, isTrue);
    });

    test('a new login during a refresh is not overwritten', () async {
      final login = AuthTokens(accessToken: valid, refreshToken: refreshValid);
      final refresh = session.refreshAccessToken(failedToken: expired);
      await pumpEventQueue();
      final start = session.start(login);

      gate.complete();
      await Future.wait([refresh, start]);

      expect(storage.tokens, same(login));
    });

    test('a refresh queued behind a logout makes no network call', () async {
      gate.complete();
      final logout = session.end();
      final refresh = session.refreshAccessToken(failedToken: expired);

      await logout;
      expect(await refresh, isNull);
      expect(requests, isEmpty);
    });

    test('a failed refresh does not block later session changes', () async {
      respond = (_) => throw http.ClientException('offline');
      final refresh = session.refreshAccessToken(failedToken: expired);
      await expectLater(refresh, throwsA(isA<Exception>()));

      await session.end();

      expect(storage.tokens, isNull);
    });
  });
}
