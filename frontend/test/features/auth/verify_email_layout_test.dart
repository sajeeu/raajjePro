import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/features/auth/presentation/widgets/otp_code_entry.dart';

import '../../helpers/pump.dart';

/// Geometry and type, measured out of `Verify Email.dc.html` with
/// `getBoundingClientRect()` and `getComputedStyle()` at the prototype's 412
/// frame — the frame `pumpScreen` pumps.
///
/// This screen came out well: the boxes were already 48 x 58 at radius 14 in
/// a centred row. The one divergence was the digit, drawn at `type.stat`
/// (18 px) where the prototype specifies 22 — in a box that was sized around
/// the larger glyph.
void main() {
  Future<void> pump(WidgetTester tester) => pumpScreen(
    tester,
    Scaffold(
      body: OtpCodeEntry(onCompleted: (_) {}, onChanged: (_) {}),
    ),
  );

  testWidgets('six boxes, 48 x 58, centred, at the prototype radius', (
    tester,
  ) async {
    await pump(tester);

    final boxes = find.descendant(
      of: find.byType(OtpCodeEntry),
      matching: find.byType(TextField),
    );
    expect(boxes, findsNWidgets(6));

    final rects = <Rect>[
      for (var i = 0; i < 6; i++) tester.getRect(boxes.at(i)),
    ];

    for (final r in rects) {
      expect(r.width, closeTo(48, 0.5), reason: 'prototype box is 48 wide');
      expect(r.height, closeTo(58, 0.5), reason: 'prototype box is 58 tall');
    }

    // One row, evenly spaced. The prototype's gap is 9; this uses
    // `AppSpacing.xxs` either side, so 8 — a 1 dp difference over five gaps,
    // left alone deliberately rather than introducing an off-scale value.
    for (var i = 1; i < 6; i++) {
      expect(rects[i].top, closeTo(rects[0].top, 0.5));
      expect(rects[i].left - rects[i - 1].right, closeTo(8, 1.5));
    }

    // Centred in the frame, as `justify-content: center` in the prototype.
    final frame = tester.getSize(find.byType(Scaffold)).width;
    final rowCentre = (rects.first.left + rects.last.right) / 2;
    expect(rowCentre, closeTo(frame / 2, 1));
  });

  testWidgets('the digit is the prototype 22 px, not the 18 px stat style', (
    tester,
  ) async {
    await pump(tester);

    final field = tester.widget<TextField>(
      find
          .descendant(
            of: find.byType(OtpCodeEntry),
            matching: find.byType(TextField),
          )
          .first,
    );
    expect(
      field.style!.fontSize,
      22,
      reason:
          'the box is 48x58 because it was drawn around a 22 px digit; '
          '`type.stat` is 18',
    );
    expect(field.style!.fontWeight, FontWeight.w800);
    expect(field.textAlign, TextAlign.center);
  });
}
