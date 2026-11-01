import 'dart:convert';

import 'package:dummy_shop/data/models/auth_tokens.dart';
import 'package:dummy_shop/data/services/token_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tokens = AuthTokens(accessToken: 'access', refreshToken: 'refresh');

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('saves both tokens as one value under a single key', () async {
    await SecureTokenStorage().save(tokens);

    final raw = await const FlutterSecureStorage().readAll();
    expect(raw.keys, [SecureTokenStorage.key]);
    expect(jsonDecode(raw[SecureTokenStorage.key]!), {
      'accessToken': 'access',
      'refreshToken': 'refresh',
    });
  });

  test('a new instance reads back what was saved', () async {
    await SecureTokenStorage().save(tokens);

    final read = await SecureTokenStorage().read();

    expect(read?.accessToken, 'access');
    expect(read?.refreshToken, 'refresh');
  });

  test('clear removes the session', () async {
    final storage = SecureTokenStorage();
    await storage.save(tokens);

    await storage.clear();

    expect(await storage.read(), isNull);
    expect(await SecureTokenStorage().read(), isNull);
  });

  test('unreadable data is treated as no session', () async {
    FlutterSecureStorage.setMockInitialValues({
      SecureTokenStorage.key: 'not json',
    });

    expect(await SecureTokenStorage().read(), isNull);
  });
}
