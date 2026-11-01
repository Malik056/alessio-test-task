import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_exception.dart';

/// Supplies and renews the bearer token for [ApiClient].
abstract interface class Authenticator {
  Future<String?> accessToken();

  /// Called after a request made with [failedToken] got a 401. Returns a new
  /// access token, or `null` if the session can't be renewed.
  Future<String?> refreshAccessToken({required String failedToken});
}

/// Thin JSON wrapper around [http.Client].
///
/// Responsibilities: build URLs, attach the bearer token (refreshing it once
/// on a 401), decode JSON and map every failure (network, timeout, non-2xx,
/// bad JSON) to an [ApiException].
class ApiClient {
  ApiClient({
    required http.Client httpClient,
    this._authenticator,
    this.baseUrl = 'https://dummyjson.com',
    this.timeout = const Duration(seconds: 15),
  }) : _http = httpClient;

  static const sessionExpiredMessage =
      'Your session has expired. Please log in again.';

  final http.Client _http;
  final Authenticator? _authenticator;
  final String baseUrl;
  final Duration timeout;

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    return _send((headers) => _http.get(uri, headers: headers));
  }

  Future<Map<String, dynamic>> post(String path, {Object? body}) {
    final uri = Uri.parse('$baseUrl$path');
    return _send(
      (headers) => _http.post(uri, headers: headers, body: jsonEncode(body)),
    );
  }

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function(Map<String, String> headers) request,
  ) async {
    final authenticator = _authenticator;
    final token = await authenticator?.accessToken();
    var response = await _perform(() => request(_headers(token)));

    if (response.statusCode == 401 && authenticator != null && token != null) {
      final newToken = await authenticator.refreshAccessToken(
        failedToken: token,
      );
      if (newToken == null) {
        throw const ApiException(sessionExpiredMessage, statusCode: 401);
      }
      response = await _perform(() => request(_headers(newToken)));
    }
    return _decode(response);
  }

  Map<String, String> _headers(String? token) => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };

  Future<http.Response> _perform(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw const ApiException('The request timed out. Please try again.');
    } on http.ClientException {
      throw const ApiException(
        'No internet connection. Please check your network.',
      );
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    final Object? decoded;
    try {
      decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    } on FormatException {
      throw ApiException(
        'Unexpected response from server.',
        statusCode: response.statusCode,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final serverMessage = decoded is Map<String, dynamic>
          ? decoded['message'] as String?
          : null;
      throw ApiException(
        serverMessage ?? 'Something went wrong (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw ApiException(
        'Unexpected response from server.',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }
}
