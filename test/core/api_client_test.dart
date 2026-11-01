import 'dart:async';
import 'dart:convert';

import 'package:dummy_shop/core/api_client.dart';
import 'package:dummy_shop/core/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeAuthenticator implements Authenticator {
  FakeAuthenticator(this.token, {this.refreshed});

  String? token;
  final String? refreshed;
  final refreshCalls = <String>[];

  @override
  Future<String?> accessToken() async => token;

  @override
  Future<String?> refreshAccessToken({required String failedToken}) async {
    refreshCalls.add(failedToken);
    return token = refreshed;
  }
}

void main() {
  ApiClient clientWith(
    MockClientHandler handler, {
    String? token,
    Duration timeout = const Duration(seconds: 15),
  }) => ApiClient(
    httpClient: MockClient(handler),
    authenticator: token == null ? null : FakeAuthenticator(token),
    baseUrl: 'https://api.test',
    timeout: timeout,
  );

  group('ApiClient', () {
    test('GET builds the URL with query params and decodes JSON', () async {
      late http.Request captured;
      final client = clientWith((request) async {
        captured = request;
        return http.Response('{"ok": true}', 200);
      });

      final json = await client.get('/products', query: {'limit': '20'});

      expect(json, {'ok': true});
      expect(captured.method, 'GET');
      expect(captured.url.toString(), 'https://api.test/products?limit=20');
    });

    test('POST sends a JSON body', () async {
      late http.Request captured;
      final client = clientWith((request) async {
        captured = request;
        return http.Response('{}', 200);
      });

      await client.post('/auth/login', body: {'username': 'u'});

      expect(captured.method, 'POST');
      expect(captured.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(captured.body), {'username': 'u'});
    });

    test('attaches the bearer token when one is stored', () async {
      late http.Request captured;
      final client = clientWith(token: 'abc', (request) async {
        captured = request;
        return http.Response('{}', 200);
      });

      await client.get('/products');

      expect(captured.headers['Authorization'], 'Bearer abc');
    });

    test('omits the Authorization header without a token', () async {
      late http.Request captured;
      final client = clientWith((request) async {
        captured = request;
        return http.Response('{}', 200);
      });

      await client.get('/products');

      expect(captured.headers.containsKey('Authorization'), isFalse);
    });

    test(
      'maps non-2xx responses to ApiException with the server message',
      () async {
        final client = clientWith(
          (_) async => http.Response('{"message": "Invalid credentials"}', 400),
        );

        await expectLater(
          client.post('/auth/login'),
          throwsA(
            isA<ApiException>()
                .having((e) => e.message, 'message', 'Invalid credentials')
                .having((e) => e.statusCode, 'statusCode', 400),
          ),
        );
      },
    );

    test('uses a generic message when the error body has none', () async {
      final client = clientWith((_) async => http.Response('', 500));

      await expectLater(
        client.get('/products'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('500'),
          ),
        ),
      );
    });

    test('maps network errors to a friendly ApiException', () async {
      final client = clientWith((_) async => throw http.ClientException('x'));

      await expectLater(
        client.get('/products'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('internet'),
          ),
        ),
      );
    });

    test('maps timeouts to ApiException', () async {
      final client = clientWith(
        timeout: const Duration(milliseconds: 10),
        (_) => Completer<http.Response>().future,
      );

      await expectLater(
        client.get('/products'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('timed out'),
          ),
        ),
      );
    });

    test('maps malformed JSON to ApiException', () async {
      final client = clientWith((_) async => http.Response('<html>', 200));

      await expectLater(client.get('/products'), throwsA(isA<ApiException>()));
    });
  });

  group('ApiClient on 401', () {
    ApiClient authed(FakeAuthenticator auth, MockClientHandler handler) =>
        ApiClient(
          httpClient: MockClient(handler),
          authenticator: auth,
          baseUrl: 'https://api.test',
        );

    test('refreshes the token once and retries the request', () async {
      final auth = FakeAuthenticator('old', refreshed: 'new');
      final sentTokens = <String?>[];
      final client = authed(auth, (request) async {
        final header = request.headers['Authorization'];
        sentTokens.add(header);
        return header == 'Bearer new'
            ? http.Response('{"ok": true}', 200)
            : http.Response('{"message": "Token Expired!"}', 401);
      });

      final json = await client.get('/auth/products');

      expect(json, {'ok': true});
      expect(auth.refreshCalls, ['old']);
      expect(sentTokens, ['Bearer old', 'Bearer new']);
    });

    test('throws a session-expired error when refresh is rejected', () async {
      final auth = FakeAuthenticator('old');
      var requests = 0;
      final client = authed(auth, (_) async {
        requests++;
        return http.Response('{"message": "Token Expired!"}', 401);
      });

      await expectLater(
        client.get('/auth/products'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)
              .having(
                (e) => e.message,
                'message',
                ApiClient.sessionExpiredMessage,
              ),
        ),
      );
      expect(requests, 1, reason: 'no retry without a new token');
    });

    test('does not loop if the retried request is also rejected', () async {
      final auth = FakeAuthenticator('old', refreshed: 'new');
      var requests = 0;
      final client = authed(auth, (_) async {
        requests++;
        return http.Response('{"message": "Forbidden"}', 401);
      });

      await expectLater(
        client.get('/auth/products'),
        throwsA(isA<ApiException>()),
      );
      expect(requests, 2);
      expect(auth.refreshCalls, hasLength(1));
    });

    test('does not try to refresh when no token was sent', () async {
      final auth = FakeAuthenticator(null);
      final client = authed(
        auth,
        (_) async => http.Response('{"message": "Unauthorized"}', 401),
      );

      await expectLater(
        client.get('/auth/me'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Unauthorized',
          ),
        ),
      );
      expect(auth.refreshCalls, isEmpty);
    });
  });
}
