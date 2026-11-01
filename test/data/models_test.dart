import 'package:dummy_shop/data/models/product.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixtures.dart';

void main() {
  group('Product.fromJson', () {
    test('parses all fields, converting ints to doubles', () {
      final p = Product.fromJson(productJson(1));

      expect(p.id, 1);
      expect(p.title, 'Product 1');
      expect(p.price, 9.99);
      expect(p.discountPercentage, 10.0);
      expect(p.brand, 'Brand');
      expect(p.images, ['https://example.com/1-1.png']);
    });

    test('tolerates a missing brand', () {
      expect(Product.fromJson(productJson(1, brand: null)).brand, isNull);
    });
  });

  group('ProductPage', () {
    test('hasMore is true while items remain', () {
      expect(page(skip: 0, count: 20, total: 194).hasMore, isTrue);
    });

    test('hasMore is false on the last page', () {
      expect(page(skip: 180, count: 14, total: 194).hasMore, isFalse);
    });

    test('parses the API envelope', () {
      final parsed = ProductPage.fromJson({
        'products': [productJson(1), productJson(2)],
        'total': 2,
        'skip': 0,
        'limit': 2,
      });

      expect(parsed.products.map((p) => p.id), [1, 2]);
      expect(parsed.hasMore, isFalse);
    });
  });
}
