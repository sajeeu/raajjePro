import 'dart:async';

import 'package:raajjepro/core/api/api_client.dart';

typedef FakeHandler = FutureOr<Map<String, dynamic>> Function(Object? body);

/// Scripted API. Register a handler per `METHOD path`; a handler may throw an
/// [ApiException] or [ApiNetworkException]. Every call is recorded.
class FakeApiClient implements ApiClient {
  final Map<String, FakeHandler> handlers = {};
  final List<({String method, String path, Object? body})> calls = [];

  /// Resolves only when [release] is called — for asserting a loading state.
  Completer<void>? gate;

  void on(String method, String path, FakeHandler handler) =>
      handlers['$method $path'] = handler;

  void fail(
    String method,
    String path, {
    required int status,
    required String code,
    Object? details,
    String message = 'failed',
  }) => on(
    method,
    path,
    (_) => throw ApiException(
      status: status,
      code: code,
      message: message,
      details: details,
    ),
  );

  void offline(String method, String path) =>
      on(method, path, (_) => throw const ApiNetworkException());

  Future<Map<String, dynamic>> _call(
    String method,
    String path,
    Object? body,
  ) async {
    calls.add((method: method, path: path, body: body));
    if (gate != null) await gate!.future;
    final handler = handlers['$method $path'];
    if (handler == null) throw StateError('unscripted call: $method $path');
    return handler(body);
  }

  @override
  Future<Map<String, dynamic>> get(String path) => _call('GET', path, null);
  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) => _call('POST', path, body);
  @override
  Future<Map<String, dynamic>> patch(String path, {Object? body}) =>
      _call('PATCH', path, body);
  @override
  Future<Map<String, dynamic>> delete(String path) =>
      _call('DELETE', path, null);
}
