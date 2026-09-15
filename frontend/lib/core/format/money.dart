/// `MVR 75` · `MVR 150` · `MVR 12.50` — code first, decimals only when the
/// value has them (`docs/design/sessions/15-admin-panel.md`'s data facts,
/// which are the app's too).
///
/// Money is integer laari everywhere it travels (invariant 7: MVR 150 =
/// 15000) and is only ever a string at the point of display, which is here.
/// Never shown as laari.
String mvr(int laari) {
  final rufiyaa = laari ~/ 100;
  final cents = laari % 100;
  if (cents == 0) return 'MVR $rufiyaa';
  return 'MVR $rufiyaa.${cents.toString().padLeft(2, '0')}';
}
