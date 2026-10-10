import 'package:raajjepro/core/public/public_copy.dart';
import 'package:raajjepro/features/saved/data/saved_api.dart';

/// Every sentence the Saved screen composes, in one place so the words are
/// testable without pumping a widget. The fixed ones are the artboard's
/// (`Discovery.dc.html`, screen "Saved").

/// "2 services · 1 provider".
String savedSubtitle({required int services, required int providers}) =>
    '$services ${services == 1 ? 'service' : 'services'} · '
    '$providers ${providers == 1 ? 'provider' : 'providers'}';

/// The saved provider row's second line: what they offer, from their
/// published services. The first line is the business name (decision 34), so
/// this is not repeated here the way the artboard repeats it under a
/// personal name.
String offersLine(SavedProvider saved) =>
    saved.categories.map((c) => c.name).join(' · ');

/// "4.6 (31)", or null with no reviews — never "0.0".
String? ratingLine(SavedProvider saved) {
  final average = averageText(saved.rating);
  return average == null ? null : '$average (${saved.rating.reviewCount})';
}

const emptyTitle = 'Nothing saved yet';
const emptyBody =
    'Tap the heart on any service or provider and it stays here. There’s no '
    'phone number to write down — this is how you remember people.';
const errorTitle = 'Saved items didn’t load';
const errorBody =
    'Everything you saved is safe — it just didn’t load this time.';
const providersIntro =
    'The people you’ve kept. There’s no number to write down — message them '
    'from here any time.';
const removedCopy = 'Removed from saved';
