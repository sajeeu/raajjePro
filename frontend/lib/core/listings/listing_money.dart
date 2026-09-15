import 'package:raajjepro/core/listings/service_listing.dart';

/// A listing's money, in the two directions a screen needs it.
///
/// 🔧 **Moved here from `features/service_wizard/`'s controller by Phase 10**,
/// on its second consumer (`lib/README.md`). §Phase 10's service card prints
/// the same string §Phase 9's step 3 shows the provider as a preview — that is
/// the point of the preview, and two implementations of it would eventually
/// disagree about the one line a provider was promised a customer would read.
///
/// Money is integer laari everywhere it travels (invariant 7: MVR 150 = 15000
/// laari) and becomes rufiyaa only here, at the last moment before it is
/// drawn. Nothing in this file uses a `double`.

/// MVR as typed → integer laari. Non-digits are dropped, so a pasted
/// "MVR 1,500" and a typed "1500" arrive at the same number.
int? laariFromMvr(String value) {
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  final rufiyaa = int.tryParse(digits);
  return rufiyaa == null ? null : rufiyaa * 100;
}

/// Whole rufiyaa for an input field. The wizard collects whole MVR, so this
/// never renders a fraction.
String mvrFromLaari(int? laari) => laari == null ? '' : '${laari ~/ 100}';

/// "MVR 450/visit", "MVR 300–900/hr", "Price on request" — what the card
/// says. §Phase 9 shows it on step 3 so a provider sees it before a customer
/// does; §Phase 10 prints it on the card that provider then manages.
String customerPricePreview(ServiceListing listing) {
  final model = listing.pricingModel;
  if (model == PricingModel.quote) return 'Price on request';
  final suffix = listing.priceUnit?.suffix ?? '';
  if (model == PricingModel.range) {
    final from = listing.priceMinLaari;
    final to = listing.priceMaxLaari;
    if (from == null || to == null) return 'MVR —$suffix';
    return 'MVR ${mvrFromLaari(from)}–${mvrFromLaari(to)}$suffix';
  }
  final price = listing.priceLaari;
  return price == null ? 'MVR —$suffix' : 'MVR ${mvrFromLaari(price)}$suffix';
}
