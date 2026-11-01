import 'dart:convert';

import 'package:dummy_shop/data/models/auth_tokens.dart';
import 'package:dummy_shop/data/models/product.dart';
import 'package:dummy_shop/data/repositories/auth_repository.dart';
import 'package:dummy_shop/data/repositories/product_repository.dart';
import 'package:dummy_shop/data/services/token_storage.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockProductRepository extends Mock implements ProductRepository {}

/// In-memory [TokenStorage] so tests don't need platform channels.
class InMemoryTokenStorage implements TokenStorage {
  InMemoryTokenStorage([this.tokens]);

  AuthTokens? tokens;

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> save(AuthTokens value) async => tokens = value;

  @override
  Future<void> clear() async => tokens = null;
}

/// An unsigned JWT whose `exp` is [expiresIn] from now (negative = expired).
String jwt(Duration expiresIn, {String id = 'x'}) {
  String part(Object json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final exp = DateTime.now().add(expiresIn).millisecondsSinceEpoch ~/ 1000;
  return '${part({'alg': 'HS256'})}.${part({'exp': exp, 'jti': id})}.sig';
}

Map<String, dynamic> productJson(int id, {String? brand = 'Brand'}) => {
  'id': id,
  'title': 'Product $id',
  'description': 'Description $id',
  'category': 'beauty',
  'price': 9.99,
  'discountPercentage': 10,
  'rating': 4.5,
  'stock': 5,
  'brand': ?brand,
  'thumbnail': 'https://example.com/$id.png',
  'images': ['https://example.com/$id-1.png'],
};

Product product(int id) => Product.fromJson(productJson(id));

/// Builds a page of products with ids `skip+1 .. skip+count`.
ProductPage page({required int skip, required int count, required int total}) =>
    ProductPage(
      products: [for (var i = 1; i <= count; i++) product(skip + i)],
      total: total,
      skip: skip,
      limit: count,
    );
