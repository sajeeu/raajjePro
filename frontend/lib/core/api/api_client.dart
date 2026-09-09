import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// One field-level problem from a `VALIDATION_FAILED`, `EMAIL_IN_USE` or
/// `PHONE_IN_USE` response: the client renders it under its field.
class FieldError {
  const FieldError({required this.path, required this.message});
  final String path;
  final String message;
}

/// The API said no. Routed on [code] — never on [message], which is for
/// display only (backend/CLAUDE.md: codes are the contract).
class ApiException implements Exception {
  ApiException({
    required this.status,
    required this.code,
    required this.message,
    this.details,
  });

  final int status;
  final String code;
  final String message;
  final Object? details;

  List<FieldError> get fieldErrors {
    final d = details;
    if (d is! List) return const [];
    return d
        .whereType<Map<String, dynamic>>()
        .map(
          (m) => FieldError(
            path: m['path'] as String? ?? '',
            message: m['message'] as String? ?? '',
          ),
        )
        .toList();
  }

  int? _detailInt(String key) {
    final d = details;
    return d is Map<String, dynamic> ? (d[key] as num?)?.toInt() : null;
  }

  String? _detailString(String key) {
    final d = details;
    return d is Map<String, dynamic> ? d[key] as String? : null;
  }

  int? get retryAfterSeconds => _detailInt('retryAfterSeconds');
  int? get attemptsRemaining => _detailInt('attemptsRemaining');
  String? get limit => _detailString('limit');

  @override
  String toString() => 'ApiException($status $code)';
}

/// The request never got an answer: no connection, DNS, timeout. Screens
/// render their offline state; nothing shows the underlying message.
class ApiNetworkException implements Exception {
  const ApiNetworkException();
}

abstract class ApiClient {
  Future<Map<String, dynamic>> get(String path);
  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Map<String, String>? headers,
  });
  Future<Map<String, dynamic>> patch(String path, {Object? body});
  Future<Map<String, dynamic>> delete(String path);
}

/// The one HTTP path to the API. Attaches the bearer token, decodes the
/// envelope, and on `ACCESS_TOKEN_EXPIRED` refreshes **once** through a single
/// shared future — ten calls failing together cause one refresh — then
/// retries each. A failed refresh or a `SESSION_EXPIRED` answer hands off to
/// [onSessionExpired] and surfaces as `SESSION_EXPIRED`.
class HttpApiClient implements ApiClient {
  // The constructor parameter is named `http` (matching the brief and the
  // `http` package import prefix); the field is `_http` to avoid colliding
  // with the `http` package import, so an initializing formal is not usable.
  HttpApiClient({
    required http.Client http,
    required this.baseUrl,
    required this.readAccessToken,
    required this.refreshTokens,
    required this.onSessionExpired,
  }) : _http = http; // ignore: prefer_initializing_formals

  final http.Client _http;
  final String baseUrl;
  Future<String?> Function() readAccessToken;
  final Future<bool> Function() refreshTokens;
  final Future<void> Function() onSessionExpired;

  /// Test hook: called after a successful refresh so a fake can rotate its token.
  void Function()? afterRefresh;

  Future<bool>? _inflightRefresh;

  @override
  Future<Map<String, dynamic>> get(String path) => _send('GET', path);

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) => _send('POST', path, body: body, extraHeaders: headers);

  @override
  Future<Map<String, dynamic>> patch(String path, {Object? body}) =>
      _send('PATCH', path, body: body);

  @override
  Future<Map<String, dynamic>> delete(String path) => _send('DELETE', path);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? extraHeaders,
    bool retried = false,
  }) async {
    // `/v1/auth/refresh` needs no access token — and attaching a bearer here
    // is worse than useless: if that endpoint itself ever answered
    // `ACCESS_TOKEN_EXPIRED`, the branch below would call `_refreshOnce()`
    // from inside the very refresh call it is nested under and await its own
    // in-flight future forever.
    final token = path == '/v1/auth/refresh' ? null : await readAccessToken();
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers['accept'] = 'application/json'
      ..headers.addAll(extraHeaders ?? const {});
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(const Duration(seconds: 20)),
      );
    } on http.ClientException {
      throw const ApiNetworkException();
    } on SocketException {
      throw const ApiNetworkException();
    } on TimeoutException {
      throw const ApiNetworkException();
    }

    final decoded = _decode(response);
    if (decoded is Map<String, dynamic> && decoded.containsKey('data')) {
      final data = decoded['data'];
      if (data is Map<String, dynamic>) return data;
      if (data is List) {
        // `meta` travels with a list under `_meta`, because a paged endpoint's
        // cursor is useless to a caller that cannot see it: dropping it here
        // left Phase 4's `GET /v1/categories` loop unable to reach page two.
        final meta = decoded['meta'];
        return {'_list': data, if (meta is Map<String, dynamic>) '_meta': meta};
      }
      return {'value': data};
    }

    final error = _errorFrom(decoded, response.statusCode);
    if (error.code == 'ACCESS_TOKEN_EXPIRED' && !retried) {
      final refreshed = await _refreshOnce();
      if (refreshed) {
        return _send(
          method,
          path,
          body: body,
          extraHeaders: extraHeaders,
          retried: true,
        );
      }
      await onSessionExpired();
      throw ApiException(
        status: 401,
        code: 'SESSION_EXPIRED',
        message: error.message,
      );
    }
    if (error.code == 'SESSION_EXPIRED') await onSessionExpired();
    throw error;
  }

  Future<bool> _refreshOnce() {
    final inflight = _inflightRefresh;
    if (inflight != null) return inflight;
    final started = refreshTokens()
        .then((ok) {
          if (ok) afterRefresh?.call();
          return ok;
        })
        .whenComplete(() => _inflightRefresh = null);
    _inflightRefresh = started;
    return started;
  }

  Object? _decode(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      return jsonDecode(response.body);
    } on FormatException {
      return null;
    }
  }

  ApiException _errorFrom(Object? decoded, int status) {
    if (decoded is Map<String, dynamic> &&
        decoded['error'] is Map<String, dynamic>) {
      final e = decoded['error'] as Map<String, dynamic>;
      return ApiException(
        status: status,
        code: e['code'] as String? ?? 'UNKNOWN',
        message: e['message'] as String? ?? 'Something went wrong',
        details: e['details'],
      );
    }
    return ApiException(
      status: status,
      code: 'UNKNOWN',
      message: 'Something went wrong',
    );
  }
}
