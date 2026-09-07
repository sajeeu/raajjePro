import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:raajjepro/core/api/api_client.dart';

void main() {
  http.Client scripted(List<http.Response Function(http.Request)> handlers) {
    var i = 0;
    return MockClient((request) async {
      final handler = handlers[i < handlers.length ? i : handlers.length - 1];
      i += 1;
      return handler(request);
    });
  }

  http.Response ok(Object data, {int status = 200}) => http.Response(
    jsonEncode({'data': data}),
    status,
    headers: {'content-type': 'application/json'},
  );

  http.Response err(int status, String code, {Object? details}) =>
      http.Response(
        jsonEncode({
          'error': {
            'code': code,
            'message': 'm',
            // ignore: use_null_aware_elements
            if (details != null) 'details': details,
          },
          'requestId': 'r',
        }),
        status,
        headers: {'content-type': 'application/json'},
      );

  HttpApiClient client(
    http.Client http, {
    Future<bool> Function()? refresh,
    Future<void> Function()? expired,
    String? token = 't1',
  }) => HttpApiClient(
    http: http,
    baseUrl: 'http://api.test',
    readAccessToken: () async => token,
    refreshTokens: refresh ?? () async => false,
    onSessionExpired: expired ?? () async {},
  );

  test('attaches the bearer token and unwraps the envelope', () async {
    late http.Request seen;
    final c = client(
      MockClient((r) async {
        seen = r;
        return ok({'id': 'u1'});
      }),
    );
    final data = await c.get('/v1/auth/me');
    expect(data['id'], 'u1');
    expect(seen.headers['authorization'], 'Bearer t1');
    expect(seen.url.toString(), 'http://api.test/v1/auth/me');
  });

  test('an error envelope becomes an ApiException routed on code, with typed details', () async {
    final c = client(
      scripted([
        (_) => err(
          409,
          'EMAIL_IN_USE',
          details: [
            {'path': 'email', 'message': 'taken'},
          ],
        ),
      ]),
    );
    try {
      await c.post('/v1/auth/register', body: {});
      fail('expected ApiException');
    } on ApiException catch (e) {
      expect(e.status, 409);
      expect(e.code, 'EMAIL_IN_USE');
      expect(e.fieldErrors.single.path, 'email');
    }
    final rl = client(
      scripted([
        (_) => err(
          429,
          'OTP_RATE_LIMITED',
          details: {'retryAfterSeconds': 272, 'limit': 'address'},
        ),
      ]),
    );
    final e = await rl
        .post('/x')
        .then<ApiException?>(
          (_) => null,
          onError: (Object e) => e as ApiException,
        );
    expect(e?.retryAfterSeconds, 272);
    expect(e?.limit, 'address');
  });

  test('ACCESS_TOKEN_EXPIRED refreshes once and retries; ten parallel calls cause one refresh', () async {
    var refreshes = 0;
    var calls = 0;
    final c = client(
      MockClient((r) async {
        calls += 1;
        return r.headers['authorization'] == 'Bearer t2'
            ? ok({'ok': true})
            : err(401, 'ACCESS_TOKEN_EXPIRED');
      }),
      refresh: () async {
        refreshes += 1;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return true;
      },
    );
    var current = 't1';
    c.readAccessToken = () async => current;
    c.afterRefresh = () {
      current = 't2';
    };
    final results = await Future.wait(
      List.generate(10, (_) => c.get('/v1/auth/me')),
    );
    expect(results.every((r) => r['ok'] == true), isTrue);
    expect(refreshes, 1);
    expect(calls, 20);
  });

  test('a failed refresh, or SESSION_EXPIRED, calls onSessionExpired and throws the code', () async {
    var expired = 0;
    final c = client(
      scripted([(_) => err(401, 'SESSION_EXPIRED')]),
      expired: () async {
        expired += 1;
      },
    );
    await expectLater(
      c.get('/x'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'SESSION_EXPIRED'),
      ),
    );
    expect(expired, 1);
    final f = client(
      scripted([(_) => err(401, 'ACCESS_TOKEN_EXPIRED')]),
      refresh: () async => false,
      expired: () async {
        expired += 1;
      },
    );
    await expectLater(
      f.get('/x'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'SESSION_EXPIRED'),
      ),
    );
    expect(expired, 2);
  });

  test(
    'a socket failure is ApiNetworkException, never a raw message',
    () async {
      final c = client(
        MockClient((_) async => throw http.ClientException('boom')),
      );
      await expectLater(c.get('/x'), throwsA(isA<ApiNetworkException>()));
    },
  );

  test('a list payload is wrapped so callers always get a map', () async {
    final c = client(
      scripted([
        (_) => ok([
          {'id': 's1'},
        ]),
      ]),
    );
    final data = await c.get('/v1/auth/sessions');
    expect((data['_list'] as List).length, 1);
  });
}
