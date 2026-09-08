import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/auth_models.dart';
import 'package:raajjepro/core/auth/device_name.dart';
import 'package:raajjepro/core/auth/token_store.dart';

import '../../helpers/fake_api.dart';

Map<String, dynamic> userJson({
  bool verified = false,
  String status = 'active',
}) => {
  'id': 'u1',
  'fullName': 'Aishath Naeema',
  'email': 'aishath@example.mv',
  'emailVerified': verified,
  'phone': {'dialCode': '+960', 'number': '7771234'},
  'status': status,
  'deletionDeadlineAt': null,
  'isProvider': false,
  'createdAt': '2026-09-06T10:00:00.000Z',
};
Map<String, dynamic> tokensJson([String suffix = '']) => {
  'accessToken': 'access$suffix',
  'accessTokenExpiresAt': '2026-09-06T10:15:00.000Z',
  'refreshToken': 'refresh$suffix',
  'refreshTokenExpiresAt': '2026-10-06T10:00:00.000Z',
};

void main() {
  late FakeApiClient api;
  late InMemoryTokenStore store;
  late ProviderContainer container;

  setUp(() {
    api = FakeApiClient();
    store = InMemoryTokenStore();
    container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStoreProvider.overrideWithValue(store),
        deviceNameProvider.overrideWith((_) async => 'Test phone'),
      ],
    );
    addTearDown(container.dispose);
  });

  test('starts unknown; restore() with no tokens → guest', () async {
    expect(container.read(authControllerProvider), isA<AuthUnknown>());
    await container.read(authControllerProvider.notifier).restore();
    expect(container.read(authControllerProvider), isA<AuthGuest>());
  });

  test('restore() with tokens loads me and is signed in; a SESSION_EXPIRED answer → sessionExpired and tokens cleared', () async {
    await store.write(TokenPair.fromJson(tokensJson()));
    api.on('GET', '/v1/auth/me', (_) => userJson(verified: true));
    await container.read(authControllerProvider.notifier).restore();
    final state = container.read(authControllerProvider);
    expect(state, isA<AuthSignedIn>());
    expect((state as AuthSignedIn).user.emailVerified, isTrue);

    api.fail('GET', '/v1/auth/me', status: 401, code: 'SESSION_EXPIRED');
    await container.read(authControllerProvider.notifier).refreshUser();
    expect(container.read(authControllerProvider), isA<AuthSessionExpired>());
    expect(await store.read(), isNull);
  });

  test('restore() with tokens; any other ApiException (500, 429, …) on a cold '
      'start reads as guest instead of stranding AuthUnknown, and keeps the tokens', () async {
    await store.write(TokenPair.fromJson(tokensJson()));
    api.fail('GET', '/v1/auth/me', status: 500, code: 'INTERNAL_ERROR');
    expect(container.read(authControllerProvider), isA<AuthUnknown>());
    await container.read(authControllerProvider.notifier).restore();
    expect(container.read(authControllerProvider), isA<AuthGuest>());
    expect(await store.read(), isNotNull);
  });

  test('signIn stores tokens with the device name and becomes signed in; a wrong password rethrows and stays guest', () async {
    api.on('POST', '/v1/auth/login', (body) {
      expect((body as Map)['deviceName'], 'Test phone');
      return {'user': userJson(), 'tokens': tokensJson()};
    });
    await container
        .read(authControllerProvider.notifier)
        .signIn('aishath@example.mv', 'pw');
    expect(container.read(authControllerProvider), isA<AuthSignedIn>());
    expect((await store.read())?.refreshToken, 'refresh');

    await container.read(authControllerProvider.notifier).signOut();
    api.fail(
      'POST',
      '/v1/auth/login',
      status: 401,
      code: 'INVALID_CREDENTIALS',
    );
    await expectLater(
      container.read(authControllerProvider.notifier).signIn('a', 'b'),
      throwsA(isA<ApiException>()),
    );
    expect(container.read(authControllerProvider), isA<AuthGuest>());
  });

  test(
    'register signs in unverified and returns the verification outcome',
    () async {
      api.on(
        'POST',
        '/v1/auth/register',
        (_) => {
          'user': userJson(),
          'tokens': tokensJson(),
          'verification': {
            'status': 'sent',
            'expiresAt': '2026-09-06T10:10:00.000Z',
            'resendAvailableAt': '2026-09-06T10:01:00.000Z',
          },
        },
      );
      final outcome = await container
          .read(authControllerProvider.notifier)
          .register(
            const RegisterRequest(
              role: AccountRole.customer,
              fullName: 'A',
              email: 'a@example.mv',
              dialCode: '+960',
              number: '7771234',
              password: 'password1',
              deviceName: 'Test phone',
            ),
          );
      expect(outcome.status, VerificationStatus.sent);
      final signedIn = container.read(authControllerProvider) as AuthSignedIn;
      expect(signedIn.user.emailVerified, isFalse);
      final call = api.calls.single;
      expect((call.body as Map)['acceptTerms'], isTrue);
      expect((call.body as Map).containsKey('businessName'), isFalse);
    },
  );

  test('tryRefresh rotates the stored pair; a failed refresh clears tokens and reports false', () async {
    await store.write(TokenPair.fromJson(tokensJson()));
    api.on('POST', '/v1/auth/refresh', (body) {
      expect((body as Map)['refreshToken'], 'refresh');
      return {'tokens': tokensJson('2')};
    });
    expect(
      await container.read(authControllerProvider.notifier).tryRefresh(),
      isTrue,
    );
    expect((await store.read())?.accessToken, 'access2');
    api.fail('POST', '/v1/auth/refresh', status: 401, code: 'SESSION_EXPIRED');
    expect(
      await container.read(authControllerProvider.notifier).tryRefresh(),
      isFalse,
    );
    expect(await store.read(), isNull);
  });

  test(
    'signOut calls logout best-effort and always ends as guest, even offline',
    () async {
      await store.write(TokenPair.fromJson(tokensJson()));
      api.on('GET', '/v1/auth/me', (_) => userJson());
      await container.read(authControllerProvider.notifier).restore();
      api.offline('POST', '/v1/auth/logout');
      await container.read(authControllerProvider.notifier).signOut();
      expect(container.read(authControllerProvider), isA<AuthGuest>());
      expect(await store.read(), isNull);
    },
  );

  test('markVerified flips the flag without a network call; applyUser replaces the user', () async {
    await store.write(TokenPair.fromJson(tokensJson()));
    api.on('GET', '/v1/auth/me', (_) => userJson());
    final c = container.read(authControllerProvider.notifier);
    await c.restore();
    c.markVerified();
    expect(
      (container.read(
        authControllerProvider,
      ) as AuthSignedIn).user.emailVerified,
      isTrue,
    );
    c.applyUser(UserAccount.fromJson(userJson(status: 'frozen')));
    expect(
      (container.read(authControllerProvider) as AuthSignedIn).user.status,
      AccountStatus.frozen,
    );
  });

  test('composition with the real HttpApiClient: an ACCESS_TOKEN_EXPIRED me() '
      'that fails to refresh reaches AuthSessionExpired via one refresh call', () async {
    var refreshCalls = 0;
    final mockHttp = MockClient((request) async {
      if (request.method == 'POST' && request.url.path == '/v1/auth/refresh') {
        refreshCalls++;
        return http.Response(
          '{"error":{"code":"SESSION_EXPIRED","message":"session expired"}}',
          401,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'GET' && request.url.path == '/v1/auth/me') {
        return http.Response(
          '{"error":{"code":"ACCESS_TOKEN_EXPIRED","message":"token expired"}}',
          401,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        '{"error":{"code":"UNKNOWN","message":"unscripted call"}}',
        404,
      );
    });
    final realStore = InMemoryTokenStore();
    await realStore.write(TokenPair.fromJson(tokensJson()));
    final realContainer = ProviderContainer(
      overrides: [
        httpClientProvider.overrideWithValue(mockHttp),
        tokenStoreProvider.overrideWithValue(realStore),
      ],
    );
    addTearDown(realContainer.dispose);

    await realContainer.read(authControllerProvider.notifier).restore();

    expect(
      realContainer.read(authControllerProvider),
      isA<AuthSessionExpired>(),
    );
    expect(await realStore.read(), isNull);
    expect(refreshCalls, 1);
  });
}
