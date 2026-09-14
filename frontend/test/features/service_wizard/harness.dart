import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/clock.dart';
import 'package:raajjepro/core/media/media_picker.dart';
import 'package:raajjepro/core/media/media_uploader.dart';
import 'package:raajjepro/core/offline/offline_queue.dart';
import 'package:raajjepro/core/offline/offline_queue_store.dart';
import 'package:raajjepro/core/offline/pending_request.dart';
import 'package:raajjepro/features/service_wizard/controller/service_wizard_controller.dart';
import 'package:raajjepro/features/service_wizard/presentation/service_wizard_screen.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/listings.dart';
import '../../helpers/pump.dart';

/// The queue's store, without a platform channel.
class FakeQueueStore implements OfflineQueueStore {
  List<PendingRequest> saved = const [];

  @override
  Future<List<PendingRequest>> read() async => saved;

  @override
  Future<void> write(List<PendingRequest> queue) async => saved = queue;
}

/// The photo library, without one either.
class FakeMediaPicker implements MediaPicker {
  FakeMediaPicker([this.result]);

  PickedImageResult? result;
  int calls = 0;

  static PickedImageResult picked() => PickedImageResult.picked(
    PickedImage(
      fileName: 'work.jpg',
      contentType: 'image/jpeg',
      bytes: Uint8List.fromList(const [1, 2, 3]),
    ),
  );

  @override
  Future<PickedImageResult> pickImage() async {
    calls++;
    return result ?? picked();
  }
}

/// The presigned PUT, without a network.
class FakeMediaUploader implements MediaUploader {
  int calls = 0;
  Object? throws;

  @override
  Future<void> put({
    required String url,
    required Map<String, String> headers,
    required Uint8List bytes,
  }) async {
    calls++;
    final failure = throws;
    if (failure != null) throw failure;
  }
}

/// Everything a wizard test drives.
class WizardHarness {
  WizardHarness()
    : api = FakeApiClient(),
      store = FakeQueueStore(),
      picker = FakeMediaPicker(),
      uploader = FakeMediaUploader();

  final FakeApiClient api;
  final FakeQueueStore store;
  final FakeMediaPicker picker;
  final FakeMediaUploader uploader;

  /// The catalogue, the account default coverage and a fresh draft — the three
  /// calls opening the wizard makes.
  void scriptFreshDraft({
    List<Map<String, dynamic>> accountServiceAreas = const [],
    Map<String, dynamic>? draft,
  }) {
    api.on('GET', '/v1/categories', (_) => {'_list': sampleCategories()});
    api.on(
      'GET',
      '/v1/providers/me',
      (_) => {'serviceAreas': accountServiceAreas},
    );
    api.on('POST', '/v1/providers/me/listings', (_) => draft ?? listingJson());
  }

  /// Every PATCH answers with [reply].
  void scriptPatch(Map<String, dynamic> Function(Object? body) reply) =>
      api.on('PATCH', '/v1/providers/me/listings/listing-1', reply);

  /// A PATCH that behaves like the server: it applies what it was sent and
  /// answers with the result.
  ///
  /// Without this a fixture that always replies with the original draft would
  /// *undo* every edit on the way back — which the wizard would faithfully
  /// adopt, because the server's answer is authoritative (invariant 4).
  void scriptEchoingPatch({Map<String, dynamic>? base}) {
    var current = base ?? listingJson();
    api.on('PATCH', '/v1/providers/me/listings/listing-1', (body) {
      final patch = body is Map<String, dynamic>
          ? body
          : const <String, dynamic>{};
      final next = Map<String, dynamic>.of(current);
      for (final entry in patch.entries) {
        // The flat fields only. A test that needs islands, media or the
        // self-declared block scripts its own reply, because those change
        // shape between the request and the response.
        if (next.containsKey(entry.key)) next[entry.key] = entry.value;
      }
      current = next;
      return next;
    });
  }

  List<Map<String, dynamic>> patchBodies() => [
    for (final call in api.calls)
      if (call.method == 'PATCH' && call.body is Map<String, dynamic>)
        call.body! as Map<String, dynamic>,
  ];

  List<Override> get overrides => [
    apiClientProvider.overrideWithValue(api),
    offlineQueueStoreProvider.overrideWithValue(store),
    mediaPickerProvider.overrideWithValue(picker),
    mediaUploaderProvider.overrideWithValue(uploader),
    clockProvider.overrideWithValue(() => DateTime.utc(2026, 9, 14)),
    // Long enough never to fire inside a test.
    offlineRetryDelayProvider.overrideWithValue(const Duration(hours: 1)),
  ];

  /// Opens the wizard **on top of another route**, so leaving it has
  /// somewhere to go. `pumpScreen` alone makes it the root, where `maybePop`
  /// can do nothing — which is a harness artefact and not the behaviour.
  Future<void> openPushed(WidgetTester tester, {String? listingId}) async {
    await pumpScreen(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ServiceWizardScreen(
                    args: ServiceWizardArgs(listingId: listingId),
                  ),
                ),
              ),
              child: const Text('Open wizard'),
            ),
          ),
        ),
      ),
      overrides: overrides,
    );
    await tester.tap(find.text('Open wizard'));
    await settle(tester);
  }

  Future<void> open(
    WidgetTester tester, {
    String? listingId,
    Map<String, WidgetBuilder> routes = const {},
  }) async {
    await pumpScreen(
      tester,
      ServiceWizardScreen(args: ServiceWizardArgs(listingId: listingId)),
      overrides: overrides,
      routes: routes,
    );
  }
}

/// Taps something that may be below the fold or off the end of the pill row.
/// A wizard step is a long scrolling form; a tap at coordinates outside the
/// viewport lands on whatever happens to be there.
Future<void> tapText(WidgetTester tester, String text) async {
  final target = find.text(text).first;
  await tester.ensureVisible(target);
  await settle(tester);
  await tester.tap(target);
  await settle(tester);
}

Future<void> tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await settle(tester);
  await tester.tap(find.byKey(key));
  await settle(tester);
}

/// Moves to a step through its pill, which is also the assertion that step
/// navigation is never blocked.
Future<void> goToStep(WidgetTester tester, String label) =>
    tapText(tester, label);

/// Types into a field and lets the autosave debounce elapse.
Future<void> typeAndSettle(WidgetTester tester, Key field, String text) async {
  final input = find.descendant(
    of: find.byKey(field),
    matching: find.byType(TextField),
  );
  await tester.ensureVisible(input);
  await settle(tester);
  await tester.enterText(input, text);
  await tester.pump();
  await tester.pump(autosaveDebounce + const Duration(milliseconds: 50));
  await settle(tester);
}
