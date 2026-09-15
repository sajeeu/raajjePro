import 'package:raajjepro/core/domain/category.dart';
import 'package:raajjepro/core/listings/service_listing.dart';
import 'package:raajjepro/core/media/media_picker.dart';

/// What the save pill says, top right of every step.
enum SaveState {
  /// "Saved just now" — the last autosave reached the server.
  saved,

  /// "Saving…" — one is in flight.
  saving,

  /// "Saved offline" — it is in the queue and will replay on reconnect.
  /// Never "not saved": it *is* saved, on this device, and that distinction
  /// is the whole point of the queue.
  offline,
}

/// Which picture an upload is for.
enum MediaTarget { cover, gallery }

/// An upload in flight, or the one that failed.
class MediaUpload {
  const MediaUpload({required this.target, required this.image, this.failure});

  final MediaTarget target;

  /// Kept so Retry re-sends the same bytes rather than re-opening the picker
  /// — a provider who chose a photo should not have to find it again.
  final PickedImage image;

  /// Null while it is still going.
  final String? failure;

  bool get failed => failure != null;
}

/// Which end-of-flow sheet is up.
enum PublishSheet { none, published, capReached }

/// §1b's cap, as the refusal reported it. The upgrade prompt names the
/// listing already live, because swapping which one is live is a real choice
/// the provider has beside upgrading.
class ListingCapDetail {
  const ListingCapDetail({required this.cap, required this.liveListingNames});

  factory ListingCapDetail.fromDetails(Object? details) {
    if (details is! Map<String, dynamic>) {
      return const ListingCapDetail(cap: 1, liveListingNames: []);
    }
    final live = details['liveListings'];
    return ListingCapDetail(
      cap: (details['activeListingCap'] as num?)?.toInt() ?? 1,
      liveListingNames: live is List
          ? live
                .whereType<Map<String, dynamic>>()
                .map((row) => (row['name'] as String? ?? '').trim())
                .where((name) => name.isNotEmpty)
                .toList(growable: false)
          : const [],
    );
  }

  final int cap;
  final List<String> liveListingNames;
}

/// Everything the wizard renders.
class WizardView {
  const WizardView({
    required this.listing,
    required this.categories,
    required this.missing,
    this.step = WizardStep.details,
    this.save = SaveState.saved,
    this.navWaiting = false,
    this.publishing = false,
    this.publishAttempted = false,
    this.sheet = PublishSheet.none,
    this.capDetail,
    this.formError,
    this.fieldErrors = const {},
    this.upload,
  });

  final ServiceListing listing;

  /// The catalogue, straight from `GET /v1/categories`. The wizard holds no
  /// fallback list: a hardcoded twelve would hide the failure §Phase 4's
  /// Done-when is about.
  final List<ServiceCategory> categories;

  /// Computed locally from [listing] so the header's counter is true the
  /// instant a field changes — including while a save is queued. The server's
  /// list is what publish answers with (invariant 4).
  final List<MissingField> missing;

  final WizardStep step;
  final SaveState save;

  /// Continue is showing "Saving this step…": navigation waits for the current
  /// step's data to persist (§Phase 9). It never waits on *validation* —
  /// every step is reachable with nothing filled in.
  final bool navWaiting;

  final bool publishing;

  /// Publish has been refused at least once, which is what turns the review
  /// step's missing-field card from a note into a warning.
  final bool publishAttempted;

  final PublishSheet sheet;
  final ListingCapDetail? capDetail;

  /// A failure with no field to hang on.
  final String? formError;

  /// Keyed by the wire field name — `name`, `priceMinLaari`. Rendered under
  /// the field, never as a toast (frontend/CLAUDE.md).
  final Map<String, String> fieldErrors;

  final MediaUpload? upload;

  /// The chosen category, or null. Resolved from the catalogue rather than
  /// stored, so every per-category number the wizard renders — the emergency
  /// window, the tier bar, the suggested tags — is the seeded one.
  ServiceCategory? get category {
    final id = listing.categoryId;
    if (id == null) return null;
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  bool get isReadyToPublish => missing.isEmpty;

  /// "3 required fields left to publish" — the framing §Phase 9 asks for,
  /// because leading with "Step 1 of 7" overstates the commitment.
  String get requirementHeadline {
    final n = missing.length;
    if (n == 0) return 'Ready to publish';
    return '$n required field${n == 1 ? '' : 's'} left to publish';
  }

  bool stepHasMissing(WizardStep step) =>
      missing.any((field) => field.step == step);

  WizardView copyWith({
    ServiceListing? listing,
    List<ServiceCategory>? categories,
    List<MissingField>? missing,
    WizardStep? step,
    SaveState? save,
    bool? navWaiting,
    bool? publishing,
    bool? publishAttempted,
    PublishSheet? sheet,
    Object? capDetail = _keep,
    Object? formError = _keep,
    Map<String, String>? fieldErrors,
    Object? upload = _keep,
  }) => WizardView(
    listing: listing ?? this.listing,
    categories: categories ?? this.categories,
    missing: missing ?? this.missing,
    step: step ?? this.step,
    save: save ?? this.save,
    navWaiting: navWaiting ?? this.navWaiting,
    publishing: publishing ?? this.publishing,
    publishAttempted: publishAttempted ?? this.publishAttempted,
    sheet: sheet ?? this.sheet,
    capDetail: capDetail == _keep
        ? this.capDetail
        : capDetail as ListingCapDetail?,
    formError: formError == _keep ? this.formError : formError as String?,
    fieldErrors: fieldErrors ?? this.fieldErrors,
    upload: upload == _keep ? this.upload : upload as MediaUpload?,
  );

  static const _keep = Object();
}
