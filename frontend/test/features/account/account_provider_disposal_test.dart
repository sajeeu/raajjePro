import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/features/account/controller/account_controller.dart';

import '../../core/auth/auth_controller_test.dart' show userJson;
import '../../helpers/fake_api.dart';

/// The account-scoped providers must not outlive the account.
///
/// `signOut` clears the token and sets `AuthGuest`. It invalidates nothing, so
/// a provider kept alive past its last listener still holds the account it was
/// built from — and `AccountController.build` applies its result to
/// `AuthState`, so a stale read propagates rather than merely displaying.
///
/// **Tested at the container, not through a screen.** A widget test cannot see
/// this: each `pumpScreen` builds a fresh `ProviderScope`, so the container is
/// new every mount and the staleness it is meant to catch cannot happen. A
/// version of this test written that way passed with auto-dispose removed —
/// a guard that proves nothing. One container, two subscriptions, is what
/// actually distinguishes the two behaviours.
void main() {
  late FakeApiClient api;
  late ProviderContainer container;

  setUp(() {
    api = FakeApiClient();
    api.on(
      'GET',
      '/v1/auth/sessions',
      (_) => {'_list': <Map<String, dynamic>>[]},
    );
    container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<String> readName() async {
    final sub = container.listen(
      accountControllerProvider.future,
      (_, _) {},
      fireImmediately: true,
    );
    final account = await sub.read();
    sub.close();
    // Auto-disposal is *scheduled*, not immediate: a listener that
    // re-subscribes inside the same tick is still served the old value. The
    // app cannot hit that — signing out, navigating and signing in take many
    // ticks — but a test that closes and re-listens synchronously can, and
    // would report a defect that is not there.
    await Future<void>.delayed(Duration.zero);
    return account.fullName;
  }

  test('a second account does not read the first one back', () async {
    api.on('GET', '/v1/auth/me', (_) => userJson());
    expect(await readName(), 'Aishath Naeema');

    // The first account signs out; the second signs in.
    api.on(
      'GET',
      '/v1/auth/me',
      (_) => {...userJson(), 'id': 'u2', 'fullName': 'Ibrahim Rasheed'},
    );

    expect(
      await readName(),
      'Ibrahim Rasheed',
      reason:
          'without isAutoDispose the provider survives its last listener and '
          'hands the next account the previous one',
    );
  });

  test('the device list does not survive either', () async {
    api.on('GET', '/v1/auth/me', (_) => userJson());
    api.on(
      'GET',
      '/v1/auth/sessions',
      (_) => {
        '_list': [
          {
            'id': 's1',
            'deviceName': 'Aishath phone',
            'createdAt': '2026-09-01T10:00:00.000Z',
            'lastSeenAt': '2026-09-09T10:00:00.000Z',
            'current': true,
          },
        ],
      },
    );
    final first = container.listen(
      sessionsControllerProvider.future,
      (_, _) {},
      fireImmediately: true,
    );
    expect((await first.read()).single.deviceName, 'Aishath phone');
    first.close();
    await Future<void>.delayed(Duration.zero);

    api.on(
      'GET',
      '/v1/auth/sessions',
      (_) => {
        '_list': [
          {
            'id': 's2',
            'deviceName': 'Ibrahim phone',
            'createdAt': '2026-09-02T10:00:00.000Z',
            'lastSeenAt': '2026-09-09T11:00:00.000Z',
            'current': true,
          },
        ],
      },
    );
    final second = container.listen(
      sessionsControllerProvider.future,
      (_, _) {},
      fireImmediately: true,
    );
    expect(
      (await second.read()).single.deviceName,
      'Ibrahim phone',
      reason: 'one account must never see another account\'s devices',
    );
    second.close();
  });
}
