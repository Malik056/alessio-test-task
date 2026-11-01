import 'dart:convert';

/// Reads the `exp` claim of a JWT without verifying it (the server does that).
/// Returns `null` if the token isn't a JWT or has no expiry.
DateTime? jwtExpiry(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    final exp = payload is Map<String, dynamic> ? payload['exp'] : null;
    return exp is int
        ? DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true)
        : null;
  } on FormatException {
    return null;
  }
}
