import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/auth/auth_controller.dart';
import 'package:raajjepro/core/listings/service_listing.dart';
import 'package:raajjepro/core/media/media_picker.dart';
import 'package:raajjepro/core/media/media_uploader.dart';
import 'package:raajjepro/core/offline/offline_queue.dart';

/// §Phase 8's owner-facing listing surface, as the wizard and the My Services
/// dashboard call it.
///
/// 🔧 **Moved here from `features/service_wizard/data/` by Phase 10**, on its
/// second consumer (`lib/README.md` — a thing a second feature needs moves to
/// `core/`, it is not copied). Phase 10 added the three calls a dashboard
/// makes and the wizard never had a reason to: [listOwn], [setVisibility] and
/// [remove].
///
/// **Every route is under `/v1/providers/me/listings`.** `/v1/listings/:id` is
/// deliberately unclaimed — §Phase 12's Service Preview and §Phase 15's search
/// define the public shape, and neither wants a body full of
/// `missingRequiredFields` and gallery upload states.
///
/// **No response here carries a phone number**, structurally: `ServiceListing`
/// has no field that could hold one (§1c — exactly one endpoint in the whole
/// system may return one to another user, and it is not any of these).
class ListingApi {
  const ListingApi(this._api, this._queue, this._uploader);

  final ApiClient _api;
  final OfflineQueue _queue;
  final MediaUploader _uploader;

  static const _base = '/v1/providers/me/listings';

  /// Page bound for [listOwn]. See its note.
  static const int _maxPages = 20;

  /// A fresh draft. Creates the provider profile implicitly where the account
  /// has none (§1a), and requires an idempotency key: without one, a double
  /// tap on a weak connection leaves two empty drafts behind and the wizard
  /// resumes into whichever it last saw.
  ///
  /// **Not queued.** There is nothing to queue *into* — every later call in
  /// this flow is addressed by the id this one returns.
  Future<ServiceListing> createDraft({String? categoryId}) async {
    final response = await _api.post(
      _base,
      body: {'categoryId': ?categoryId},
      headers: {'idempotency-key': _queue.newIdempotencyKey('listing.create')},
    );
    return ServiceListing.fromJson(response);
  }

  Future<ServiceListing> read(String listingId) async =>
      ServiceListing.fromJson(await _api.get('$_base/$listingId'));

  /// Every listing this provider still has — drafts and published together,
  /// in the order the server returns them.
  ///
  /// **Paged to the end**, the way `CategoryApi.list` is. §Phase 8 pages this
  /// endpoint because a paid provider has no ceiling on drafts, and §Phase
  /// 10's dashboard has to count *all* of them: its stats row is a total, and
  /// a filter that only searched the first page would tell a provider they
  /// have no drafts while a draft sat on page two. The status filter the
  /// endpoint offers is deliberately **not** used — the three filter pills
  /// switch instantly over what is already loaded, and re-fetching per pill
  /// would make the totals disagree with the list under them.
  Future<List<ServiceListing>> listOwn() async {
    final all = <ServiceListing>[];
    String? cursor;
    // Bounded, for the reason `CategoryApi.list` is: a server handing back
    // the same cursor forever would otherwise hang the dashboard on its
    // skeleton with no error to show. 20 pages of 50 is 1,000 listings — far
    // past any real provider and far short of a hang.
    for (var page = 0; page < _maxPages; page++) {
      final query = cursor == null
          ? ''
          : '&cursor=${Uri.encodeQueryComponent(cursor)}';
      final response = await _api.get('$_base?limit=50$query');
      // `ApiClient` unwraps the envelope: a list payload arrives as `_list`
      // and the envelope's `meta` as `_meta` (`CategoryApi` records what
      // reading `data` here costs — an empty state over a perfectly good
      // 200).
      final data = response['_list'];
      if (data is! List) break;
      all.addAll(
        data.whereType<Map<String, dynamic>>().map(ServiceListing.fromJson),
      );
      final meta = response['_meta'];
      cursor = meta is Map<String, dynamic>
          ? meta['nextCursor'] as String?
          : null;
      if (cursor == null) break;
    }
    return List.unmodifiable(all);
  }

  /// The live toggle, and the only two values §1b makes the provider's:
  /// `active` and `hidden_by_provider`. `hidden_over_cap` belongs to the
  /// entitlement system and `hidden_by_admin` to moderation — the server
  /// refuses either here, which is what keeps "upgrade restores exactly what
  /// downgrade hid" true (§1b, Round 17).
  ///
  /// **Not queued.** A provider who toggles a service live offline and is
  /// told it is live would be told something false about what customers can
  /// see; §0.0 item 14 holds the queue to three surfaces and this is not one.
  Future<ServiceListing> setVisibility(
    String listingId,
    ListingVisibility visibility,
  ) async => ServiceListing.fromJson(
    await _api.patch(
      '$_base/$listingId/visibility',
      body: {'visibility': visibility.wire},
    ),
  );

  /// §1b's "the provider can override the choice from the dashboard"
  /// (§Phase 10) — which of their published listings stays visible when the
  /// entitlement cap cannot hold all of them.
  ///
  /// **It sets a pin, not a visibility.** `hidden_over_cap` is the
  /// entitlement system's value alone (§1b, Round 17), so the server records
  /// the preference and re-runs its own reconcile; the listing this one
  /// displaces stays `hidden_over_cap` and comes back on upgrade. The
  /// alternative the client could have assembled — hide one, activate the
  /// other — would write `hidden_by_provider` onto a listing the system hid
  /// and quietly break that restore
  /// (`docs/decisions/25-phase-10-two-questions-answered.md`).
  ///
  /// Returns this listing. **Another listing has changed too**, which is why
  /// the dashboard re-reads rather than patching one row.
  Future<ServiceListing> keepVisible(String listingId) async =>
      ServiceListing.fromJson(
        await _api.post('$_base/$listingId/keep-visible'),
      );

  /// Invariant 8 — the server stamps `deletedAt`. The row, its media, its
  /// service areas and its event log all stay, so a booking or a review that
  /// referenced this listing still resolves; what changes is that customers
  /// can no longer find it.
  Future<ServiceListing> remove(String listingId) async =>
      ServiceListing.fromJson(await _api.delete('$_base/$listingId'));

  /// One PATCH per wizard step, half-filled steps included — invariant 2's
  /// "a draft must be saveable with zero required fields filled".
  ///
  /// **This is the queued one.** It returns null when the network refused it
  /// and it went into the queue instead, which is the caller's signal to show
  /// "Saved offline" rather than a result. Ten offline keystrokes merge into
  /// one queued PATCH, because a PATCH is a partial update and the merge is
  /// exactly what the server would have ended up with.
  ///
  /// No idempotency key: a PATCH is not a creation and a replayed partial
  /// update converges on the same row.
  Future<ServiceListing?> patch(
    String listingId,
    Map<String, dynamic> body,
  ) async {
    final response = await _queue.submit(
      _queue.request(
        method: 'PATCH',
        path: '$_base/$listingId',
        label: wizardAutosaveLabel,
        mergeKey: 'listing:$listingId:patch',
        body: body,
      ),
    );
    return response == null ? null : ServiceListing.fromJson(response);
  }

  /// The only door from draft to live, and where the six required fields, the
  /// entitlement cap, the pricing/booking-mode rule and §1c's emergency gate
  /// are all enforced.
  ///
  /// **Never queued.** Telling a provider their service is live when the
  /// request has not left the device would be a lie, and the queue holds
  /// exactly three surfaces (§0.0 item 14) of which this is not one.
  /// Idempotent, so a lost response on a flaky connection does not turn a
  /// second attempt into a cap breach.
  Future<ServiceListing> publish(String listingId) async {
    final response = await _api.post(
      '$_base/$listingId/publish',
      headers: {'idempotency-key': _queue.newIdempotencyKey('listing.publish')},
    );
    return ServiceListing.fromJson(response);
  }

  /// §Phase 8's three-step presigned upload, from the client's side.
  ///
  ///  1. Ask for a target — the server chooses the object key, never us.
  ///  2. PUT the bytes to it, outside [ApiClient] and with no bearer token.
  ///  3. Ask the server to finalise: it reads the bytes back, sniffs their
  ///     real type, checks their real size and strips their metadata. Until
  ///     that returns, the row is `pending` and the publish gate treats it as
  ///     a missing cover.
  Future<ListingMedia> uploadImage(String listingId, PickedImage image) async {
    final created = await _api.post(
      '$_base/$listingId/media',
      body: {'contentType': image.contentType},
      headers: {
        'idempotency-key': _queue.newIdempotencyKey('listing.media.create'),
      },
    );
    final media = ListingMedia.fromJson(
      created['media'] as Map<String, dynamic>? ?? const {},
    );
    final upload = created['upload'] as Map<String, dynamic>? ?? const {};
    await _uploader.put(
      url: upload['url'] as String? ?? '',
      headers: {
        for (final entry
            in (upload['headers'] as Map<String, dynamic>? ?? const {}).entries)
          entry.key: '${entry.value}',
      },
      bytes: image.bytes,
    );
    return ListingMedia.fromJson(
      await _api.post('$_base/$listingId/media/${media.id}/complete'),
    );
  }

  /// Invariant 8 — stamps `removedAt`; the object stays in the store. Removing
  /// the cover clears it and makes the listing incomplete again, but does not
  /// unpublish it. Returns the listing, because the server has just changed
  /// two things about it.
  Future<ServiceListing> removeMedia(String listingId, String mediaId) async =>
      ServiceListing.fromJson(
        await _api.delete('$_base/$listingId/media/$mediaId'),
      );
}

/// What the offline screen calls a queued wizard save, in the provider's
/// words (`App States.dc.html`).
const wizardAutosaveLabel = 'Saving a step of the service wizard';

final listingApiProvider = Provider<ListingApi>(
  (ref) => ListingApi(
    ref.watch(apiClientProvider),
    ref.watch(offlineQueueProvider.notifier),
    ref.watch(mediaUploaderProvider),
  ),
);
