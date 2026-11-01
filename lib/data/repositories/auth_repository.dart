import '../../core/api_client.dart';
import '../models/auth_tokens.dart';
import '../models/user.dart';
import '../services/session_manager.dart';

class AuthRepository {
  AuthRepository({required ApiClient apiClient, required this._session})
    : _api = apiClient;

  final ApiClient _api;
  final SessionManager _session;

  /// Logs in and persists the tokens. Throws [ApiException] on failure.
  Future<User> login({
    required String username,
    required String password,
  }) async {
    final json = await _api.post(
      '/auth/login',
      body: {'username': username, 'password': password},
    );
    final user = User.fromJson(json);
    await _session.start(AuthTokens.fromJson(json));
    return user;
  }

  /// Startup check; refreshes the access token only if it has expired.
  Future<bool> restoreSession() => _session.restore();

  Future<void> logout() => _session.end();
}
