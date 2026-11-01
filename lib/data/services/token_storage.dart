import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/auth_tokens.dart';

/// Persists the auth tokens. Abstracted so the session logic can be tested
/// without platform channels.
abstract interface class TokenStorage {
  Future<AuthTokens?> read();
  Future<void> save(AuthTokens tokens);
  Future<void> clear();
}

/// Stores the tokens in the iOS Keychain / Android Keystore-backed storage.
///
/// Both tokens are one JSON value under a single key, so every write is
/// all-or-nothing: storage never holds an access token without its refresh
/// token, even if the app is killed mid-write.
///
/// Keeps an in-memory copy so we don't hit the platform channel on every
/// request.
class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const key = 'auth_tokens';

  final FlutterSecureStorage _storage;
  AuthTokens? _cached;
  bool _loaded = false;

  @override
  Future<AuthTokens?> read() async {
    if (!_loaded) {
      _cached = _decode(await _storage.read(key: key));
      _loaded = true;
    }
    return _cached;
  }

  @override
  Future<void> save(AuthTokens tokens) async {
    await _storage.write(key: key, value: jsonEncode(tokens.toJson()));
    _cached = tokens;
    _loaded = true;
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: key);
    _cached = null;
    _loaded = true;
  }

  /// Unreadable data is treated as "no session" rather than crashing startup.
  static AuthTokens? _decode(String? value) {
    if (value == null) return null;
    try {
      return AuthTokens.fromJson(jsonDecode(value) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
