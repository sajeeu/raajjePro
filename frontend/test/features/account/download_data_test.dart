import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/auth/token_store.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/features/account/controller/account_controller.dart';
import 'package:raajjepro/features/account/presentation/download_data_screen.dart';
import 'package:raajjepro/shared/shared.dart';
import 'package:share_plus/share_plus.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump.dart';

/// Lets a widget test land the screen directly on one [DownloadState] —
/// `request()` writes a real temp file (see account_controller.dart), which
/// is genuine `dart:io` work FakeAsync's fake clock cannot advance, so the
/// state-rendering tests below drive the state directly rather than through
/// a real tap. The plain, non-widget test further down exercises `request()`
/// for real, with real async allowed to complete normally.
class _FixedDownloadController extends DownloadController {
  _FixedDownloadController(this._state);
  final DownloadState _state;
  @override
  DownloadState build() => _state;
}

void main() {
  late FakeApiClient api;
  setUp(() => api = FakeApiClient());

  Future<void> pump(WidgetTester tester, {List<Override> extra = const []}) =>
      pumpScreen(
        tester,
        const DownloadDataScreen(),
        overrides: [
          apiClientProvider.overrideWithValue(api),
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          ...extra,
        ],
      );

  testWidgets(
    'default lists the four items and Request my data; never mentions email',
    (tester) async {
      await pump(tester);
      for (final t in [
        'Profile details',
        'Bookings and their records',
        'Reviews you wrote',
        'Message history',
        'Request my data',
      ]) {
        expect(find.textContaining(t), findsWidgets);
      }
      final body = tester.allWidgets
          .whereType<Text>()
          .map((t) => t.data ?? '')
          .join(' | ');
      expect(body.toLowerCase().contains('email'), isFalse);
    },
  );

  testWidgets('tapping shows the button\'s own loading', (tester) async {
    api.gate = Completer<void>();
    api.on(
      'GET',
      '/v1/users/me/data-export',
      (_) => {
        'profile': {'fullName': 'Aishath Naeema'},
      },
    );
    await pump(tester);
    await tester.tap(find.text('Request my data'));
    await tester.pump();
    expect(find.byType(AppSpinner), findsOneWidget);
    // Release the gate so nothing is left mid-request when the test ends;
    // the resulting real file write is not awaited here (see the plain
    // `request()` test below for that), only the loading state matters.
    api.gate!.complete();
    await tester.pump();
  });

  testWidgets('shared: the ready notice, never mentioning email', (
    tester,
  ) async {
    await pump(
      tester,
      extra: [
        downloadControllerProvider.overrideWith(
          () => _FixedDownloadController(const DownloadState(shared: true)),
        ),
      ],
    );
    expect(
      find.text(
        'Your export is ready — saved or shared from the sheet you chose.',
      ),
      findsOneWidget,
    );
    final body = tester.allWidgets
        .whereType<Text>()
        .map((t) => t.data ?? '')
        .join(' | ');
    expect(body.toLowerCase().contains('email'), isFalse);
  });

  testWidgets('offline shows the inline notice with retry', (tester) async {
    api.offline('GET', '/v1/users/me/data-export');
    await pump(tester);
    await tester.tap(find.text('Request my data'));
    await settle(tester);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('failed shows a distinct error notice', (tester) async {
    await pump(
      tester,
      extra: [
        downloadControllerProvider.overrideWith(
          () => _FixedDownloadController(const DownloadState(failed: true)),
        ),
      ],
    );
    expect(
      find.text("Couldn't prepare your export. Try again in a moment."),
      findsOneWidget,
    );
  });

  test('request() fetches the export, names the file for the date, hands it to the share sheet, and clears a stale export left by an earlier run', () async {
    final realApi = FakeApiClient();
    realApi.on(
      'GET',
      '/v1/users/me/data-export',
      (_) => {
        'profile': {'fullName': 'Aishath Naeema'},
      },
    );
    final shared = <XFile>[];
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(realApi),
        tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 9, 6)),
        shareProvider.overrideWithValue((file) async {
          shared.add(file);
        }),
      ],
    );
    addTearDown(container.dispose);

    // A stale export from an earlier run, sitting in the same temp
    // directory `request()` writes to.
    final staleFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}raajjepro-export-2020-01-01.json',
    );
    await staleFile.writeAsBytes(utf8.encode('{}'));
    addTearDown(() async {
      if (await staleFile.exists()) await staleFile.delete();
    });

    await container.read(downloadControllerProvider.notifier).request();

    final freshFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}raajjepro-export-2026-09-06.json',
    );
    addTearDown(() async {
      if (await freshFile.exists()) await freshFile.delete();
    });

    expect(container.read(downloadControllerProvider).shared, isTrue);
    expect(shared, hasLength(1));
    expect(shared.single.name, 'raajjepro-export-2026-09-06.json');
    final bytes = await shared.single.readAsBytes();
    expect(jsonDecode(utf8.decode(bytes)), {
      'profile': {'fullName': 'Aishath Naeema'},
    });

    // The stale export is gone — cleared before the new one was written,
    // never right after sharing (a share target may still be reading it).
    expect(await staleFile.exists(), isFalse);
    expect(await freshFile.exists(), isTrue);
  });
}
