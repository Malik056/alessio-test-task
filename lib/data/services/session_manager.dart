import '../../core/api_client.dart';
import '../../core/api_exception.dart';
import '../../core/jwt.dart';
import '../models/auth_tokens.dart';
import 'token_storage.dart';

/// Owns the token lifecycle: storing, validating on startup, refreshing and
/// ending the session.
class SessionManager implements Authenticator {
  SessionManager({
    required this._storage,
    required this._authApi,
    this.expiryLeeway = const Duration(seconds: 30),
  });

  final TokenStorage _storage;

  /// Client *without* an authenticator, so a failing refresh can't recurse.
  final ApiClient _authApi;

  /// Treat tokens as expired slightly early to absorb clock skew and latency.
  final Duration expiryLeeway;

  Future<String?>? _refreshing;

  Future<void> start(AuthTokens tokens) => _storage.save(tokens);

  Future<void> end() => _storage.clear();

  /// Startup check. Returns whether the user can continue without logging in.
  ///
  /// Works offline when the access token is still valid. Refreshes only if
  /// it has expired. If the refresh fails for a transient reason (offline,
  /// timeout, 5xx), the session is kept and the next launch retries.
  Future<bool> restore() async {
    final tokens = await _storage.read();
    if (tokens == null) return false;
    if (!_isExpired(tokens.accessToken)) return true;

    if (_isExpired(tokens.refreshToken)) {
      await _storage.clear();
      return false;
    }
    try {
      return await _refreshOnce() != null;
    } on ApiException {
      return true;
    }
  }

  @override
  Future<String?> accessToken() async => (await _storage.read())?.accessToken;

  @override
  Future<String?> refreshAccessToken({required String failedToken}) async {
    final current = await _storage.read();
    if (current == null) return null;
    // Another request already refreshed while this one was in flight.
    if (current.accessToken != failedToken) return current.accessToken;
    return _refreshOnce();
  }

  /// Concurrent callers share one network call. Servers that invalidate a
  /// refresh token on use would otherwise reject the second, parallel refresh.
  Future<String?> _refreshOnce() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  /// Returns `null` and ends the session if the server rejects the refresh
  /// token; the caller then surfaces an [ApiException] for the request.
  Future<String?> _refresh() async {
    final tokens = await _storage.read();
    if (tokens == null) return null;
    try {
      final fresh = AuthTokens.fromJson(
        await _authApi.post(
          '/auth/refresh',
          body: {'refreshToken': tokens.refreshToken},
        ),
      );
      await _storage.save(fresh);
      return fresh.accessToken;
    } on ApiException catch (e) {
      final status = e.statusCode;
      // Network failures and server errors don't mean the session is invalid.
      if (status == null || status >= 500) rethrow;
      await _storage.clear();
      return null;
    }
  }

  bool _isExpired(String token) {
    final expiry = jwtExpiry(token);
    // Opaque tokens can't be checked locally; rely on the server's 401.
    if (expiry == null) return false;
    return DateTime.now().toUtc().isAfter(expiry.subtract(expiryLeeway));
  }
}
