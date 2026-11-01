import 'package:dummy_shop/core/api_exception.dart';
import 'package:dummy_shop/data/repositories/product_repository.dart';
import 'package:dummy_shop/ui/products/product_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../helpers/fixtures.dart';

void main() {
  late MockProductRepository repository;

  setUp(() => repository = MockProductRepository());

  Widget app() => Provider<ProductRepository>.value(
    value: repository,
    child: const MaterialApp(home: ProductListScreen()),
  );

  testWidgets('shows the empty state', (tester) async {
    when(() => repository.fetchProducts(skip: 0, limit: 20))
        .thenAnswer((_) async => page(skip: 0, count: 0, total: 0));

    await tester.pumpWidget(app());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('No products found.'), findsOneWidget);
  });

  testWidgets('shows the error state and retries', (tester) async {
    when(() => repository.fetchProducts(skip: 0, limit: 20))
        .thenThrow(const ApiException('No internet connection.'));

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('No internet connection.'), findsOneWidget);

    when(() => repository.fetchProducts(skip: 0, limit: 20))
        .thenAnswer((_) async => page(skip: 0, count: 0, total: 0));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('No products found.'), findsOneWidget);
  });
}
