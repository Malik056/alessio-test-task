import 'package:dummy_shop/app.dart';
import 'package:dummy_shop/ui/login/login_screen.dart';
import 'package:dummy_shop/ui/products/product_list_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/fixtures.dart';

void main() {
  late MockAuthRepository auth;
  late MockProductRepository products;

  setUp(() {
    auth = MockAuthRepository();
    products = MockProductRepository();
    when(() => products.fetchProducts(skip: 0, limit: 20))
        .thenAnswer((_) async => page(skip: 0, count: 0, total: 0));
  });

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      DummyShopApp(authRepository: auth, productRepository: products),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('starts on the product list when the session restores', (
    tester,
  ) async {
    when(() => auth.restoreSession()).thenAnswer((_) async => true);

    await pumpApp(tester);

    expect(find.byType(ProductListView), findsOneWidget);
  });

  testWidgets('starts on login when there is no valid session', (tester) async {
    when(() => auth.restoreSession()).thenAnswer((_) async => false);

    await pumpApp(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
