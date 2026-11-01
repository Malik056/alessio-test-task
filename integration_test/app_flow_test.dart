import 'dart:convert';

import 'package:dummy_shop/data/models/auth_tokens.dart';
import 'package:dummy_shop/data/services/token_storage.dart';
import 'package:dummy_shop/main.dart' as app;
import 'package:dummy_shop/ui/login/login_screen.dart';
import 'package:dummy_shop/ui/product_detail/product_detail_screen.dart';
import 'package:dummy_shop/ui/products/product_list_screen.dart';
import 'package:dummy_shop/ui/products/product_list_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

/// End-to-end against the real https://dummyjson.com API.
/// Run with: flutter test integration_test
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // A fresh instance each time, so nothing is served from the in-memory cache.
  Future<AuthTokens?> storedTokens() => SecureTokenStorage().read();

  Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 100 && finder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final error = find.byKey(const Key('login_error'));
    if (finder.evaluate().isEmpty && error.evaluate().isNotEmpty) {
      fail('Login error: ${tester.widget<Text>(error).data}');
    }
    expect(finder, findsWidgets);
  }

  // Sets the field's text through its controller. `enterText` is unreliable on
  // a real iOS simulator: the platform keyboard can overwrite injected values
  // in secure (password) fields after they lose focus.
  Future<void> type(WidgetTester tester, String key, String text) async {
    final editable = find.descendant(
      of: find.byKey(Key(key)),
      matching: find.byType(EditableText),
    );
    tester.widget<EditableText>(editable).controller.text = text;
    await tester.pumpAndSettle();
  }

  testWidgets('login → paginate → detail → logout', (tester) async {
    await const FlutterSecureStorage().deleteAll();
    app.main();
    await tester.pumpAndSettle();

    // Wrong password shows the server error.
    await type(tester, 'login_username', 'emilys');
    await type(tester, 'login_password', 'nope');
    await tester.tap(find.byKey(const Key('login_submit')));
    await pumpUntil(tester, find.byKey(const Key('login_error')));
    expect(find.text('Invalid credentials'), findsOneWidget);

    // Correct credentials navigate to the list and persist the token.
    await type(tester, 'login_password', 'emilyspass');
    await tester
        .pumpAndSettle(); // editing clears the error and moves the button
    await tester.tap(find.byKey(const Key('login_submit')));
    await pumpUntil(tester, find.byType(ProductTile));
    expect((await storedTokens())?.accessToken, isNotEmpty);

    // Scrolling to the end of the first page loads the next one.
    final viewModel = Provider.of<ProductListViewModel>(
      tester.element(find.byType(ProductListView)),
      listen: false,
    );
    expect(viewModel.products, hasLength(20));
    for (var i = 0; i < 10 && viewModel.products.length <= 20; i++) {
      await tester.fling(find.byType(ListView), const Offset(0, -3000), 3000);
      await tester.pumpAndSettle();
    }
    expect(viewModel.products.length, greaterThan(20));
    expect(
      viewModel.products.map((p) => p.id).toSet(),
      hasLength(viewModel.products.length),
      reason: "pages must not overlap",
    );

    // Opening a product shows its detail page.
    await tester.fling(find.byType(ListView), const Offset(0, 5000), 5000);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ProductTile).first);
    await tester.pumpAndSettle();
    expect(find.byType(ProductDetailScreen), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);

    // Back, then log out clears the token and returns to login.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Log out'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login_submit')), findsOneWidget);
    // Logout clears storage in the background; give it a moment.
    for (var i = 0; i < 20 && await storedTokens() != null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(await storedTokens(), isNull);
  });

  group('startup with a stored session', () {
    // A structurally valid JWT that expired an hour ago.
    String expiredJwt() {
      String part(Object json) =>
          base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
      final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 3600;
      return '${part({'alg': 'HS256'})}.${part({'exp': exp})}.sig';
    }

    Future<String> realRefreshToken() async {
      final response = await http.post(
        Uri.parse('https://dummyjson.com/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': 'emilys', 'password': 'emilyspass'}),
      );
      return (jsonDecode(response.body) as Map)['refreshToken'] as String;
    }

    testWidgets('expired access token is refreshed silently', (tester) async {
      final expired = expiredJwt();
      await SecureTokenStorage().save(
        AuthTokens(
          accessToken: expired,
          refreshToken: await realRefreshToken(),
        ),
      );

      app.main();
      await pumpUntil(tester, find.byType(ProductTile));

      final access = (await storedTokens())?.accessToken;
      expect(access, isNot(expired));
      expect(access, isNotEmpty);
    });

    testWidgets('rejected refresh token lands on login', (tester) async {
      await SecureTokenStorage().save(
        AuthTokens(accessToken: expiredJwt(), refreshToken: 'revoked'),
      );

      app.main();
      await pumpUntil(tester, find.byType(LoginScreen));

      expect(await storedTokens(), isNull);
    });
  });
}
