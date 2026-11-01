import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/repositories/auth_repository.dart';
import 'data/repositories/product_repository.dart';
import 'ui/startup/startup_screen.dart';

class DummyShopApp extends StatelessWidget {
  const DummyShopApp({
    super.key,
    required this.authRepository,
    required this.productRepository,
  });

  final AuthRepository authRepository;
  final ProductRepository productRepository;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: authRepository),
        Provider.value(value: productRepository),
      ],
      child: MaterialApp(
        title: 'Dummy Shop',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.indigo),
        darkTheme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
        ),
        home: const StartupScreen(),
      ),
    );
  }
}
