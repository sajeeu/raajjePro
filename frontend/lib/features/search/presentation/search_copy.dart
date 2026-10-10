import 'package:raajjepro/core/domain/category.dart' show BookingMode;
import 'package:raajjepro/core/public/public_copy.dart';
import 'package:raajjepro/features/search/data/search_api.dart';

/// The results screen's words, `Discovery.dc.html`'s except where noted.

const errorTitle = "Results didn't load";

/// The prototype's sentence. The second half matters: an empty-looking
/// failure must not be mistaken for "nothing matched".
const errorBodyOffline =
    'Your connection dropped. Nothing was filtered out — this is a loading '
    'problem.';

/// A server failure is not a dropped connection, and the copy says which
/// (decision 33's precedent on Explore).
const errorBodyServer =
    "We couldn't reach RaajjePro just then. Nothing was filtered out — this is "
    'a loading problem.';

const noMatchTitle = 'No services matched';

const loadMoreFailed = "Couldn't load more results.";

String serviceCount(int n) => n == 1 ? '1 service' : '$n services';

/// The price chip: "Price" until a bound is set, then the range as typed.
String priceLabel(SearchFilters f) {
  final min = f.priceMinMvr;
  final max = f.priceMaxMvr;
  if (min != null && max != null) return 'MVR $min–$max';
  if (min != null) return 'From MVR $min';
  if (max != null) return 'Up to MVR $max';
  return 'Price';
}

String modeLabel(BookingMode? mode) => mode == null ? 'Mode' : bookingCta(mode);

const maldivianOwnedLabel = 'Maldivian-owned';

/// The filtered-out empty state names what is doing the filtering, the way
/// the prototype does ("‘Under MVR 300’ and ‘Hulhumalé’ are filtering
/// everything out"). The prototype goes on to explain *why*, e.g. "services
/// on Hulhumalé currently start above MVR 300", which the server does not
/// compute, so this stops at naming them and asking the customer to remove one.
String filteredOutBody(List<String> active) {
  final quoted = active.map((a) => '‘$a’').toList();
  final names = switch (quoted.length) {
    0 => '',
    1 => quoted.single,
    _ =>
      '${quoted.sublist(0, quoted.length - 1).join(', ')} and ${quoted.last}',
  };
  final verb = quoted.length == 1 ? 'is' : 'are';
  return '$names $verb filtering everything out. Try removing one.';
}

/// A search that matched nothing with no filter set.
String unmatchedBody(String query) => query.trim().isEmpty
    ? 'Nothing is on offer here yet. Try another island, or browse the '
          'categories.'
    : 'Nothing on offer matches “${query.trim()}” yet. Try a different word, '
          'or browse the categories.';

/// Category results with nothing in them.
String categoryEmptyTitle(String category, String? island) => island == null
    ? 'No $category providers yet'
    : 'No $category providers on $island yet';

/// The prototype opens "Providers join every week", a growth claim the
/// product cannot promise on launch day, so it is dropped (decision 36).
const categoryEmptyBody =
    'Most categories are still filling in island by island. Try another '
    'island, or browse everything on offer today.';

/// The Filters sheet's price note (approved design, 2026-10-10). A quote
/// listing has no price to compare, so it drops out while a bound is set.
const priceNote = 'Price-on-request services are hidden while a price is set.';

/// §1g. The attribute is evidenced at Gold. The wording says what was
/// checked, never "Maldivian" about a person.
const maldivianOwnedTitle = 'Maldivian-owned business';
const maldivianOwnedNote = 'Verified at Gold';
