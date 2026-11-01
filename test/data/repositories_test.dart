import 'dart:convert';

import 'package:dummy_shop/core/api_client.dart';
import 'package:dummy_shop/core/api_exception.dart';
import 'package:dummy_shop/data/models/auth_tokens.dart';
import 'package:dummy_shop/data/repositories/auth_repository.dart';
import 'package:dummy_shop/data/repositories/product_repository.dart';
import 'package:dummy_shop/data/services/session_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/fixtures.dart';

void main() {
  ApiClient apiWith(MockClientHandler handler) =>
      ApiClient(httpClient: MockClient(handler), baseUrl: 'https://api.test');

  group('AuthRepository', () {
    late InMemoryTokenStorage storage;

    setUp(() => storage = InMemoryTokenStorage());

    AuthRepository repoWith(MockClientHandler handler) {
      final api = apiWith(handler);
      return AuthRepository(
        apiClient: api,
        session: SessionManager(storage: storage, authApi: api),
      );
    }

    test('login posts credentials and stores both tokens', () async {
      late http.Request captured;
      final access = jwt(const Duration(hours: 1));
      final repo = repoWith((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'id': 1,
            'username': 'emilys',
            'firstName': 'Emily',
            'lastName': 'Johnson',
            'email': 'emily@x.com',
            'image': '',
            'accessToken': access,
            'refreshToken': 'refresh-123',
          }),
          200,
        );
      });

      final user = await repo.login(username: 'emilys', password: 'pw');

      expect(captured.url.path, '/auth/login');
      expect(jsonDecode(captured.body), {
        'username': 'emilys',
        'password': 'pw',
      });
      expect(user.username, 'emilys');
      expect(storage.tokens?.accessToken, access);
      expect(storage.tokens?.refreshToken, 'refresh-123');
      expect(await repo.restoreSession(), isTrue);
    });

    test('failed login does not store tokens', () async {
      final repo = repoWith(
        (_) async => http.Response('{"message":"Invalid credentials"}', 400),
      );

      await expectLater(
        repo.login(username: 'x', password: 'y'),
        throwsA(isA<ApiException>()),
      );
      expect(storage.tokens, isNull);
      expect(await repo.restoreSession(), isFalse);
    });

    test('logout clears the tokens', () async {
      storage.tokens = AuthTokens(
        accessToken: jwt(const Duration(hours: 1)),
        refreshToken: 'r',
      );
      final repo = repoWith((_) async => http.Response('{}', 200));

      await repo.logout();

      expect(storage.tokens, isNull);
      expect(await repo.restoreSession(), isFalse);
    });
  });

  group('ProductRepository', () {
    test('requests the page with skip/limit and parses it', () async {
      late http.Request captured;
      final repo = ProductRepository(
        apiClient: apiWith((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'products': [productJson(21), productJson(22)],
              'total': 30,
              'skip': 20,
              'limit': 2,
            }),
            200,
          );
        }),
      );

      final result = await repo.fetchProducts(skip: 20, limit: 2);

      expect(captured.url.path, '/products');
      expect(captured.url.queryParameters, {'skip': '20', 'limit': '2'});
      expect(result.products.map((p) => p.id), [21, 22]);
      expect(result.hasMore, isTrue);
    });
  });
}
