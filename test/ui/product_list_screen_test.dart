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

  testWidgets('failed next page retries, then offers Try again', (
    tester,
  ) async {
    when(() => repository.fetchProducts(skip: 0, limit: 20))
        .thenAnswer((_) async => page(skip: 0, count: 2, total: 40));
    when(() => repository.fetchProducts(skip: 2, limit: 20))
        .thenThrow(const ApiException('No internet connection.'));

    await tester.pumpWidget(app());
    // Not pumpAndSettle: the footer spinner animates while more pages exist.
    await tester.pump();
    await tester.pump();

    // Pulling up at the bottom triggers the next page, which fails.
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(find.text('Connection problem. Retrying…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    verify(() => repository.fetchProducts(skip: 2, limit: 20)).called(3);

    when(() => repository.fetchProducts(skip: 2, limit: 20))
        .thenAnswer((_) async => page(skip: 2, count: 2, total: 4));
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(find.text('Product 3'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });
}
