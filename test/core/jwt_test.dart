import 'package:dummy_shop/core/jwt.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';

void main() {
  group('jwtExpiry', () {
    test('reads the exp claim', () {
      final expiry = jwtExpiry(jwt(const Duration(hours: 1)))!;

      expect(
        expiry.difference(DateTime.now().toUtc()).inMinutes,
        inInclusiveRange(59, 60),
      );
    });

    test('returns null for non-JWT tokens', () {
      expect(jwtExpiry('opaque-token'), isNull);
      expect(jwtExpiry('a.!!!.c'), isNull);
    });

    test('returns null when there is no exp claim', () {
      // {"alg":"HS256"}.{"sub":"1"}
      expect(jwtExpiry('eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig'), isNull);
    });
  });
}
