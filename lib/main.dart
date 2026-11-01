import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app.dart';
import 'core/api_client.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/product_repository.dart';
import 'data/services/session_manager.dart';
import 'data/services/token_storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Composition root: the only place concrete implementations are wired up.
  final httpClient = http.Client();
  // Login/refresh must not go through the refresh-on-401 logic.
  final authApi = ApiClient(httpClient: httpClient);
  final session = SessionManager(
    storage: SecureTokenStorage(),
    authApi: authApi,
  );
  final apiClient = ApiClient(httpClient: httpClient, authenticator: session);

  runApp(
    DummyShopApp(
      authRepository: AuthRepository(apiClient: authApi, session: session),
      productRepository: ProductRepository(apiClient: apiClient),
    ),
  );
}
