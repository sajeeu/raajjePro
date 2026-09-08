import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/features/account/presentation/account_settings_screen.dart';
import 'package:raajjepro/shared/shared.dart';

import '../../core/auth/auth_controller_test.dart' show userJson;
import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

/// §Phase 3c Done-when: "the app exposes no toggle for booking notifications".
///
/// Booking notifications are transactional and always sent. "Always enabled"
/// means *we do not offer a switch* — the OS can still revoke the permission,
/// and that case is exactly what the email fallback and the persistent
/// reminder exist for.
///
/// Two assertions, because either one alone is weak: the rendered screen has
/// no such control today, and no source file introduces one tomorrow. Phase 19
/// adds Marketing and Weekly digest toggles under a fixed line saying booking
/// updates have no switch — those are opt-in sends and are unaffected.
void main() {
  testWidgets('Account settings renders no notification switch at all', (
    tester,
  ) async {
    final api = FakeApiClient();
    api.on('GET', '/v1/auth/me', (_) => userJson());
    api.on(
      'GET',
      '/v1/auth/sessions',
      (_) => {'_list': <Map<String, dynamic>>[]},
    );

    await pumpScreen(
      tester,
      const AccountSettingsScreen(),
      overrides: [
        apiClientProvider.overrideWithValue(api),
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      ],
    );

    expect(find.byType(AppToggle), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(
      find.textContaining('notification', findRichText: true),
      findsNothing,
    );
    expect(
      find.textContaining('Notification', findRichText: true),
      findsNothing,
    );
  });

  test('no screen wires a toggle to a booking-notification setting', () {
    // A grep, deliberately: the rule is about the whole app, not one screen,
    // and the next person to add a settings row will not read this file first.
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      final hasToggle =
          source.contains('AppToggle') || source.contains('Switch(');
      if (!hasToggle) continue;
      final mentionsNotifications =
          source.toLowerCase().contains('notification') ||
          source.toLowerCase().contains('push');
      // The gallery renders every shared widget with sample data, including
      // AppToggle — it is a component catalogue, not a settings screen.
      final isGallery = entity.path.contains('/gallery/');
      if (mentionsNotifications && !isGallery) offenders.add(entity.path);
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Booking notifications are transactional and have no switch '
          '(§Phase 3c). Phase 19 adds Marketing and Weekly digest toggles — '
          'if that is what this is, put it behind the fixed line the plan '
          'specifies and update this test.',
    );
  });
}
