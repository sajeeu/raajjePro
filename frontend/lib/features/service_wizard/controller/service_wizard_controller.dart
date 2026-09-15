import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:raajjepro/core/api/api_client.dart';
import 'package:raajjepro/core/categories/categories_controller.dart';
import 'package:raajjepro/core/domain/category.dart';
import 'package:raajjepro/core/domain/island.dart';
import 'package:raajjepro/core/feedback/app_haptics.dart';
import 'package:raajjepro/core/listings/listing_api.dart';
import 'package:raajjepro/core/listings/listing_money.dart';
import 'package:raajjepro/core/listings/service_listing.dart';
import 'package:raajjepro/core/location/account_service_areas.dart';
import 'package:raajjepro/core/media/media_picker.dart';
import 'package:raajjepro/core/media/media_uploader.dart';
import 'package:raajjepro/core/offline/offline_queue.dart';
import 'package:raajjepro/features/service_wizard/controller/wizard_view.dart';
import 'package:raajjepro/features/service_wizard/data/publish_gate.dart';

/// Up to 10 (§Phase 8's schema, and step 1's own helper line).
const int maxListingTags = 10;

/// The gallery beyond the cover. `Create Service.dc.html`'s own number; the
/// API accepts more, so this is the tighter of the two and cannot be refused.
const int maxGalleryPhotos = 8;

/// How long after the last keystroke a step's autosave fires.
const Duration autosaveDebounce = Duration(milliseconds: 600);

/// Which listing the wizard opened on.
///
/// **No id means a fresh draft** — §Phase 6a hands off here with nothing in
/// arguments precisely so the provider starts from an empty step 1 rather
/// than in whatever they last touched (ledger P6A-2). An id means resume or
/// edit, which is how §Phase 10's dashboard will open one.
class ServiceWizardArgs {
  const ServiceWizardArgs({this.listingId});

  factory ServiceWizardArgs.fromRouteArguments(Object? arguments) {
    if (arguments is ServiceWizardArgs) return arguments;
    if (arguments is Map && arguments['listingId'] is String) {
      return ServiceWizardArgs(listingId: arguments['listingId'] as String);
    }
    return const ServiceWizardArgs();
  }

  final String? listingId;
}

// `retry: null`: the screen renders its own error with a Try again, and
// Riverpod 3's default would silently retry a failed `build()` for ~30s
// behind it (frontend/CLAUDE.md).
Duration? _noRetry(int retryCount, Object error) => null;

/// Keyed on the listing id — **a `String?`, not the arguments object**. A
/// family key is compared by value, and a fresh `ServiceWizardArgs` built on
/// every widget build would key a brand-new provider on every frame.
final serviceWizardControllerProvider =
    AsyncNotifierProvider.family<ServiceWizardController, WizardView, String?>(
      ServiceWizardController.new,
      isAutoDispose: true,
      retry: _noRetry,
    );

/// The Create/Edit Service Wizard (§Phase 9).
///
/// ## Three rules shape everything below
///
/// **A draft saves with zero required fields filled** (invariant 2). Nothing
/// here validates on the way in; every step PATCHes whatever is there and the
/// six required fields are enforced only at publish, by the server.
///
/// **Step navigation is never blocked by validation** — Review is reachable
/// from step 1 with nothing typed. It *is* delayed by persistence: Continue
/// shows "Saving this step…" while the current step's autosave is in flight,
/// which is §Phase 9's "step navigation is blocked until the current step's
/// data has persisted". Offline that wait is instant, because the queue
/// accepting the write *is* persistence.
///
/// **The server decides, this renders.** Emergency eligibility, the callback
/// guarantee's availability and the publish gate are all the backend's
/// (invariant 4). The one rule mirrored here is the required-field count, and
/// only because the header shows it on every keystroke — `publish_gate.dart`
/// says why.
class ServiceWizardController extends AsyncNotifier<WizardView> {
  ServiceWizardController(this.listingId);

  /// Null for a fresh draft; an id resumes or edits an existing listing.
  final String? listingId;

  Timer? _debounce;
  final Map<String, dynamic> _pending = {};
  Future<void>? _inFlight;

  /// Bumped on every local edit. A server response is adopted only when no
  /// newer edit has happened since its request went out — otherwise a slow
  /// PATCH would land on top of what the provider has since typed.
  int _edits = 0;

  /// Set the moment this notifier starts being torn down. `ref.mounted` alone
  /// is not enough: a save or an upload can land while the provider is
  /// already on another screen, and Riverpod refuses a `state` write from
  /// there. Same guard as [OfflineQueue]'s, for the same reason.
  bool _disposed = false;

  bool get _alive => !_disposed && ref.mounted && state.hasValue;

  @override
  Future<WizardView> build() async {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _debounce?.cancel();
      _debounce = null;
    });

    final categories = await ref.watch(categoriesControllerProvider.future);
    final api = ref.read(listingApiProvider);
    final id = listingId;
    final listing = id == null
        ? await _startFreshDraft(api)
        : await api.read(id);

    // The queue draining in the background is what turns "Saved offline" back
    // into "Saved just now" — the wizard is not the one that replayed it.
    ref.listen<OfflineState>(offlineQueueProvider, (
      OfflineState? previous,
      OfflineState next,
    ) {
      if (!_alive) return;
      if (next.hasPending) {
        _set(_view.copyWith(save: SaveState.offline));
      } else if (_view.save == SaveState.offline) {
        _set(_view.copyWith(save: SaveState.saved));
      }
    });

    return WizardView(
      listing: listing,
      categories: categories,
      missing: missingRequiredFields(listing),
    );
  }

  /// A brand-new draft, pre-filled with the account's default coverage.
  ///
  /// §Phase 6a's step 4 hands off "pre-populated with nothing (a fresh
  /// draft)", and §Phase 9's step 2 is "pre-filled from your default coverage
  /// areas". Both are true at once: the *listing* starts empty and the
  /// islands are copied across once, here, at the moment it is created.
  ///
  /// **Copied, not shared** (ledger P7-3). After this write the listing owns
  /// its islands — editing them never touches the account default, and the
  /// account default never reaches back in. Doing it at creation is also what
  /// makes it happen exactly once: a provider who clears every island and
  /// comes back to step 2 does not find them silently restored.
  Future<ServiceListing> _startFreshDraft(ListingApi api) async {
    final draft = await api.createDraft();
    final defaults = await ref.read(accountServiceAreasApiProvider).read();
    if (defaults.isEmpty) return draft;
    final saved = await api.patch(draft.id, {
      'serviceAreaIslandIds': [for (final island in defaults) island.id],
    });
    return saved ?? draft.copyWith(serviceAreas: defaults);
  }

  WizardView get _view => state.requireValue;

  void _set(WizardView view) {
    if (!_alive) return;
    state = AsyncData(view);
  }

  Future<void> reload() async {
    state = const AsyncLoading<WizardView>();
    state = await AsyncValue.guard(build);
  }

  // ---------------------------------------------------------------------------
  // Saving
  // ---------------------------------------------------------------------------

  /// Applies an edit locally, then schedules the PATCH that persists it.
  ///
  /// [immediate] is for discrete controls — a chip, a radio, a toggle. A
  /// provider who taps a category and immediately taps Continue should not
  /// wait out a debounce that exists for typing.
  void _edit(
    ServiceListing next,
    Map<String, dynamic> patch, {
    bool immediate = false,
  }) {
    _edits++;
    _pending.addAll(patch);
    _set(
      _view.copyWith(
        listing: next,
        missing: missingRequiredFields(next),
        formError: null,
        fieldErrors: const {},
      ),
    );
    _debounce?.cancel();
    if (immediate) {
      unawaited(flush());
      return;
    }
    _debounce = Timer(autosaveDebounce, () {
      _debounce = null;
      unawaited(flush());
    });
  }

  /// Sends whatever is waiting, and waits for whatever is already in flight.
  /// Navigation and publish both go through here, so neither can act on data
  /// the server has not been told about.
  Future<void> flush() async {
    _debounce?.cancel();
    _debounce = null;
    await _inFlight;
    if (_pending.isEmpty || !_alive) return;

    final body = Map<String, dynamic>.of(_pending);
    _pending.clear();
    final at = _edits;
    _set(_view.copyWith(save: SaveState.saving));

    final request = _send(_view.listing.id, body, at);
    _inFlight = request;
    try {
      await request;
    } finally {
      if (identical(_inFlight, request)) _inFlight = null;
    }
  }

  Future<void> _send(
    String listingId,
    Map<String, dynamic> body,
    int at,
  ) async {
    try {
      final saved = await ref.read(listingApiProvider).patch(listingId, body);
      if (!_alive) return;
      if (saved == null) {
        // Queued. The local state already carries the edit, and the queue
        // carries the write — nothing is lost and nothing is pretended.
        _set(_view.copyWith(save: SaveState.offline));
        return;
      }
      if (_edits == at) {
        _set(
          _view.copyWith(
            listing: saved,
            missing: missingRequiredFields(saved),
            save: SaveState.saved,
          ),
        );
      } else {
        _set(_view.copyWith(save: SaveState.saved));
      }
    } on ApiException catch (e) {
      if (!_alive) return;
      // The server refused the edit, so the screen and the row now disagree.
      // Re-read rather than guess: the provider needs to see what actually
      // stuck before they carry on.
      final fields = {
        for (final error in e.fieldErrors)
          error.path.split('.').last: error.message,
      };
      _set(
        _view.copyWith(
          save: SaveState.saved,
          fieldErrors: fields,
          formError: fields.isEmpty ? e.message : null,
        ),
      );
      await _resync();
    }
  }

  Future<void> _resync() async {
    if (!_alive) return;
    try {
      final fresh = await ref.read(listingApiProvider).read(_view.listing.id);
      if (!_alive) return;
      _set(
        _view.copyWith(listing: fresh, missing: missingRequiredFields(fresh)),
      );
    } on ApiException {
      // Leave what is on screen; the provider has an error already.
    } on ApiNetworkException {
      _set(_view.copyWith(save: SaveState.offline));
    }
  }

  /// The offline banner's retry, and the app coming back to the foreground.
  Future<void> retryQueued() =>
      ref.read(offlineQueueProvider.notifier).retryNow();

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  /// Never refused. A step with nothing in it is a step a provider may leave,
  /// and Review is reachable from anywhere.
  Future<void> goTo(WizardStep step) async {
    if (step == _view.step) return;
    final waiting = _pending.isNotEmpty || _inFlight != null;
    if (waiting) {
      _set(_view.copyWith(navWaiting: true));
      await flush();
      if (!_alive) return;
      _set(_view.copyWith(navWaiting: false));
    }
    _set(_view.copyWith(step: step, formError: null));
  }

  Future<void> next() async {
    final index = _view.step.index;
    if (index >= WizardStep.values.length - 1) return;
    await goTo(WizardStep.values[index + 1]);
  }

  Future<void> back() async {
    final index = _view.step.index;
    if (index == 0) return;
    await goTo(WizardStep.values[index - 1]);
  }

  // ---------------------------------------------------------------------------
  // Step 1 — Details
  // ---------------------------------------------------------------------------

  void setName(String value) {
    final trimmed = value.isEmpty ? null : value;
    _edit(_view.listing.copyWith(name: trimmed), {'name': trimmed});
  }

  void setShortDescription(String value) {
    final trimmed = value.isEmpty ? null : value;
    _edit(_view.listing.copyWith(shortDescription: trimmed), {
      'shortDescription': trimmed,
    });
  }

  void setLongDescription(String value) {
    final trimmed = value.isEmpty ? null : value;
    _edit(_view.listing.copyWith(longDescription: trimmed), {
      'longDescription': trimmed,
    });
  }

  /// Choosing a category re-defaults the booking mode from the seed (§1c) and
  /// drops the previous category's suggested tags, which were suggestions for
  /// a different trade. Anything the provider typed themselves is kept.
  ///
  /// `isEmergency` and the callback guarantee may also stop being allowed, and
  /// the **server** decides that — it clears them in the same write, and the
  /// response is what this adopts.
  void chooseCategory(ServiceCategory category) {
    if (_view.listing.categoryId == category.id) return;
    final previous = _view.category?.suggestedTags ?? const <String>[];
    final kept = [
      for (final tag in _view.listing.tags)
        if (!previous.contains(tag)) tag,
    ];
    _edit(
      _view.listing.copyWith(
        categoryId: category.id,
        bookingMode: category.bookingMode,
        tags: kept,
      ),
      {'categoryId': category.id, 'tags': kept},
      immediate: true,
    );
  }

  /// A suggested chip. Selecting past the cap does nothing — step 1's helper
  /// line says "Up to 10" and the chips stop responding, rather than a toast
  /// telling a provider off after the fact.
  void toggleTag(String tag) {
    final tags = _view.listing.tags;
    if (tags.contains(tag)) {
      _setTags([
        for (final existing in tags)
          if (existing != tag) existing,
      ]);
      return;
    }
    if (tags.length >= maxListingTags) return;
    _setTags([...tags, tag]);
  }

  /// The free-text field underneath the chips (Round 12). Returns false where
  /// there was nothing to add, so the field can say why.
  bool addCustomTag(String raw) {
    final tag = raw.trim();
    if (tag.isEmpty) return false;
    final tags = _view.listing.tags;
    if (tags.contains(tag) || tags.length >= maxListingTags) return false;
    _setTags([...tags, tag]);
    return true;
  }

  void _setTags(List<String> tags) {
    _edit(_view.listing.copyWith(tags: tags), {'tags': tags}, immediate: true);
  }

  // ---------------------------------------------------------------------------
  // Step 2 — Location
  // ---------------------------------------------------------------------------

  /// The whole set, every time: this step is a multi-select and the PATCH
  /// replaces what is there. Island **ids**, never names — sixteen normalised
  /// names occur in more than one atoll (§0.0 item 12).
  void setServiceAreas(List<Island> islands) {
    _edit(_view.listing.copyWith(serviceAreas: islands), {
      'serviceAreaIslandIds': [for (final island in islands) island.id],
    }, immediate: true);
  }

  // ---------------------------------------------------------------------------
  // Step 3 — Pricing
  // ---------------------------------------------------------------------------

  /// `range` and `quote` force request mode (§Phase 8) — nobody can book a set
  /// time at an unknown price. Applied here as well as on the server so step
  /// 5's radio is already correct when the provider gets to it.
  void choosePricingModel(PricingModel model) {
    if (_view.listing.pricingModel == model) return;
    final forced =
        model.forcesRequestMode &&
        _view.listing.bookingMode != BookingMode.request;
    _edit(
      _view.listing.copyWith(
        pricingModel: model,
        bookingMode: forced ? BookingMode.request : null,
      ),
      {
        'pricingModel': model.wire,
        if (forced) 'bookingMode': BookingMode.request.name,
      },
      immediate: true,
    );
  }

  void setPrice(String mvr) {
    final laari = laariFromMvr(mvr);
    _edit(_view.listing.copyWith(priceLaari: laari), {'priceLaari': laari});
  }

  void setPriceMin(String mvr) {
    final laari = laariFromMvr(mvr);
    _edit(_view.listing.copyWith(priceMinLaari: laari), {
      'priceMinLaari': laari,
    });
  }

  void setPriceMax(String mvr) {
    final laari = laariFromMvr(mvr);
    _edit(_view.listing.copyWith(priceMaxLaari: laari), {
      'priceMaxLaari': laari,
    });
  }

  void choosePriceUnit(PriceUnit unit) {
    _edit(_view.listing.copyWith(priceUnit: unit), {
      'priceUnit': unit.wire,
    }, immediate: true);
  }

  // ---------------------------------------------------------------------------
  // Step 4 — Media
  // ---------------------------------------------------------------------------

  Future<void> pickCover() => _pickAndUpload(MediaTarget.cover);

  Future<void> addGalleryPhoto() => _pickAndUpload(MediaTarget.gallery);

  /// Re-sends the bytes that failed. The provider does not find the photo
  /// again — that is what [MediaUpload.image] is kept for.
  Future<void> retryUpload() async {
    final failed = _view.upload;
    if (failed == null || !failed.failed) return;
    await _upload(failed.target, failed.image);
  }

  void dismissUpload() => _set(_view.copyWith(upload: null));

  Future<void> _pickAndUpload(MediaTarget target) async {
    final result = await ref.read(mediaPickerProvider).pickImage();
    final image = result.image;
    if (image == null) {
      final message = _pickFailureMessage(result.failure);
      if (message != null) _set(_view.copyWith(formError: message));
      return;
    }
    await _upload(target, image);
  }

  Future<void> _upload(MediaTarget target, PickedImage image) async {
    _set(
      _view.copyWith(
        formError: null,
        upload: MediaUpload(target: target, image: image),
      ),
    );
    try {
      final media = await ref
          .read(listingApiProvider)
          .uploadImage(_view.listing.id, image);
      if (!_alive) return;
      _set(_view.copyWith(upload: null));
      if (target == MediaTarget.cover) {
        _edit(_view.listing.copyWith(coverMedia: media), {
          'coverMediaId': media.id,
        }, immediate: true);
      } else {
        final gallery = [..._view.listing.gallery, media];
        _edit(_view.listing.copyWith(gallery: gallery), {
          'galleryMediaIds': [for (final row in gallery) row.id],
        }, immediate: true);
      }
    } on ApiNetworkException {
      _failUpload(
        target,
        image,
        'That upload needs a connection. Your other changes are saved.',
      );
    } on MediaUploadException {
      _failUpload(target, image, 'The upload did not finish. Try again.');
    } on ApiException catch (e) {
      _failUpload(target, image, e.message);
    }
  }

  void _failUpload(MediaTarget target, PickedImage image, String message) {
    if (!_alive) return;
    _set(
      _view.copyWith(
        upload: MediaUpload(target: target, image: image, failure: message),
      ),
    );
  }

  static String? _pickFailureMessage(PickFailure? failure) => switch (failure) {
    PickFailure.unsupportedType =>
      'That file type is not supported — use a JPG, PNG or WEBP.',
    PickFailure.tooLarge => 'That photo is over 10 MB. Try a smaller one.',
    _ => null,
  };

  /// Invariant 8 — the image is withdrawn, never destroyed. Removing the cover
  /// makes the listing incomplete again; it does not take a live service away
  /// from a customer.
  Future<void> removeMedia(String mediaId) async {
    await flush();
    try {
      final listing = await ref
          .read(listingApiProvider)
          .removeMedia(_view.listing.id, mediaId);
      if (!_alive) return;
      _set(
        _view.copyWith(
          listing: listing,
          missing: missingRequiredFields(listing),
        ),
      );
    } on ApiNetworkException {
      _set(
        _view.copyWith(
          formError: 'Removing a photo needs a connection. Try again shortly.',
        ),
      );
    } on ApiException catch (e) {
      _set(_view.copyWith(formError: e.message));
    }
  }

  /// "Use the arrows to reorder — the first photo shows first."
  void moveGalleryPhoto(int index, int delta) {
    final gallery = [..._view.listing.gallery];
    final target = index + delta;
    if (index < 0 || index >= gallery.length) return;
    if (target < 0 || target >= gallery.length) return;
    final moved = gallery.removeAt(index);
    gallery.insert(target, moved);
    _edit(_view.listing.copyWith(gallery: gallery), {
      'galleryMediaIds': [for (final row in gallery) row.id],
    }, immediate: true);
  }

  // ---------------------------------------------------------------------------
  // Step 5 — Availability
  // ---------------------------------------------------------------------------

  /// Refused where the pricing model forces request mode; the card renders the
  /// reason rather than silently ignoring the tap.
  void chooseBookingMode(BookingMode mode) {
    final model = _view.listing.pricingModel;
    if (mode == BookingMode.slot && (model?.forcesRequestMode ?? false)) return;
    if (_view.listing.bookingMode == mode) return;
    _edit(_view.listing.copyWith(bookingMode: mode), {
      'bookingMode': mode.name,
    }, immediate: true);
  }

  /// ISO weekday, 1 = Monday.
  void toggleWorkingDay(int day) {
    final days = _view.listing.workingDays;
    final next = days.contains(day)
        ? [
            for (final existing in days)
              if (existing != day) existing,
          ]
        : ([...days, day]..sort());
    _edit(_view.listing.copyWith(workingDays: next), {
      'workingDays': next,
    }, immediate: true);
  }

  void setWorkingHours({String? from, String? to}) {
    _edit(
      _view.listing.copyWith(
        workingHoursFrom: from ?? _view.listing.workingHoursFrom,
        workingHoursTo: to ?? _view.listing.workingHoursTo,
      ),
      {'workingHoursFrom': ?from, 'workingHoursTo': ?to},
      immediate: true,
    );
  }

  /// Only ever reachable when the **server** said it is allowed
  /// (`listing.emergency.allowed`). Nothing here compares a tier to a bar —
  /// that rule is §1c's, composed from four fields across three entities, and
  /// it lives on the backend.
  void toggleEmergency() {
    if (!_view.listing.emergency.allowed) return;
    final next = !_view.listing.isEmergency;
    _edit(_view.listing.copyWith(isEmergency: next), {
      'isEmergency': next,
    }, immediate: true);
  }

  // ---------------------------------------------------------------------------
  // Step 6 — Extra information
  // ---------------------------------------------------------------------------

  void setWhatsIncluded(String value) {
    final text = value.isEmpty ? null : value;
    _edit(_view.listing.copyWith(whatsIncluded: text), {'whatsIncluded': text});
  }

  void setWhatsNotIncluded(String value) {
    final text = value.isEmpty ? null : value;
    _edit(_view.listing.copyWith(whatsNotIncluded: text), {
      'whatsNotIncluded': text,
    });
  }

  bool addFaq(String question, String answer) {
    if (question.trim().isEmpty || answer.trim().isEmpty) return false;
    final faqs = [
      ..._view.listing.faqs,
      ListingFaq(question: question.trim(), answer: answer.trim()),
    ];
    _setFaqs(faqs);
    return true;
  }

  void removeFaq(int index) {
    final faqs = [..._view.listing.faqs];
    if (index < 0 || index >= faqs.length) return;
    faqs.removeAt(index);
    _setFaqs(faqs);
  }

  void _setFaqs(List<ListingFaq> faqs) {
    _edit(_view.listing.copyWith(faqs: faqs), {
      'faqs': [for (final faq in faqs) faq.toJson()],
    }, immediate: true);
  }

  void toggleWarranty() {
    final next = !_view.listing.selfDeclared.warrantyOffered;
    _edit(
      _view.listing.copyWith(
        selfDeclared: _view.listing.selfDeclared.copyWith(
          warrantyOffered: next,
        ),
      ),
      {'warrantyOffered': next},
      immediate: true,
    );
  }

  void setWarrantyText(String value) {
    final text = value.isEmpty ? null : value;
    _edit(
      _view.listing.copyWith(
        selfDeclared: _view.listing.selfDeclared.copyWith(
          warrantyTermsText: text,
        ),
      ),
      {'warrantyTermsText': text},
    );
  }

  void toggleInsurance() {
    final next = !_view.listing.selfDeclared.insuranceDeclared;
    _edit(
      _view.listing.copyWith(
        selfDeclared: _view.listing.selfDeclared.copyWith(
          insuranceDeclared: next,
        ),
      ),
      {'insuranceDeclared': next},
      immediate: true,
    );
  }

  void setInsuranceText(String value) {
    final text = value.isEmpty ? null : value;
    _edit(
      _view.listing.copyWith(
        selfDeclared: _view.listing.selfDeclared.copyWith(
          insuranceDetailText: text,
        ),
      ),
      {'insuranceDetailText': text},
    );
  }

  /// Only where the category is `callbackEligible` — and on one that is not,
  /// step 6 renders no control at all (Round 28: absent, not disabled), so
  /// this is unreachable there rather than merely guarded.
  void toggleCallbackGuarantee() {
    if (!_view.listing.callbackAvailable) return;
    final next = !_view.listing.callbackGuaranteeOffered;
    _edit(_view.listing.copyWith(callbackGuaranteeOffered: next), {
      'callbackGuaranteeOffered': next,
    }, immediate: true);
  }

  // ---------------------------------------------------------------------------
  // Step 7 — Review & publish
  // ---------------------------------------------------------------------------

  /// The only door from draft to live.
  ///
  /// Two refusals matter and they are deliberately different codes:
  /// `LISTING_INCOMPLETE` carries a row per missing field with the step it
  /// belongs to, so each one gets its own Fix link; `LISTING_CAP_REACHED` is
  /// the upgrade prompt (§Phase 9 — "an upgrade prompt, not a generic
  /// error"). Collapsing them would make the second unanswerable.
  Future<void> publish() async {
    await flush();
    if (!_alive) return;

    if (_view.missing.isNotEmpty) {
      // The app said no, and it says so by moving the provider to Review and
      // marking the gaps — a change they may not be looking at the moment
      // they tap. §Phase 1's record: a refusal and a success must never feel
      // the same.
      AppHaptics.refused();
      _set(
        _view.copyWith(
          publishAttempted: true,
          step: WizardStep.review,
          formError: null,
        ),
      );
      return;
    }

    _set(_view.copyWith(publishing: true, formError: null));
    try {
      final published = await ref
          .read(listingApiProvider)
          .publish(_view.listing.id);
      if (!_alive) return;
      // Live, and not quietly undoable — the one moment in this flow that
      // earns more than a selection tick.
      AppHaptics.commit();
      _set(
        _view.copyWith(
          listing: published,
          missing: missingRequiredFields(published),
          publishing: false,
          sheet: PublishSheet.published,
        ),
      );
    } on ApiNetworkException {
      _set(
        _view.copyWith(
          publishing: false,
          formError:
              'Publishing needs a connection. Your draft is saved — try again '
              'when you are back online.',
        ),
      );
    } on ApiException catch (e) {
      _handlePublishRefusal(e);
    }
  }

  void _handlePublishRefusal(ApiException e) {
    if (!_alive) return;
    AppHaptics.refused();
    switch (e.code) {
      case 'LISTING_INCOMPLETE':
        final details = e.details;
        final missing = details is List
            ? [
                for (final row in details.whereType<Map<String, dynamic>>())
                  MissingField.fromJson(row),
              ]
            : _view.missing;
        _set(
          _view.copyWith(
            listing: _view.listing.copyWith(missingRequiredFields: missing),
            missing: missing,
            publishing: false,
            publishAttempted: true,
            step: WizardStep.review,
          ),
        );
      case 'LISTING_CAP_REACHED':
        _set(
          _view.copyWith(
            publishing: false,
            sheet: PublishSheet.capReached,
            capDetail: ListingCapDetail.fromDetails(e.details),
          ),
        );
      default:
        // A rule that is not about completeness — the pricing/booking-mode
        // pair, the emergency gate, the callback guarantee. The message names
        // both fields; send the provider to the step that owns the first.
        final field = e.fieldErrors.isEmpty
            ? null
            : e.fieldErrors.first.path.split('.').last;
        _set(
          _view.copyWith(
            publishing: false,
            publishAttempted: true,
            formError: e.message,
            step: _stepForField(field) ?? _view.step,
          ),
        );
    }
  }

  static WizardStep? _stepForField(String? field) => switch (field) {
    'pricingModel' ||
    'priceLaari' ||
    'priceMinLaari' ||
    'priceMaxLaari' => WizardStep.pricing,
    'bookingMode' || 'isEmergency' => WizardStep.availability,
    'callbackGuaranteeOffered' => WizardStep.extras,
    'categoryId' || 'name' || 'shortDescription' => WizardStep.details,
    'serviceAreaIslandIds' => WizardStep.location,
    'coverMediaId' || 'galleryMediaIds' => WizardStep.media,
    _ => null,
  };

  void dismissSheet() => _set(_view.copyWith(sheet: PublishSheet.none));

  void clearFormError() => _set(_view.copyWith(formError: null));
}
