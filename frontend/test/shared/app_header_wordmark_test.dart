import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/shared/shared.dart';

import '../helpers/pump.dart';

/// The wordmark is a brand mark, not content, so it does not scale with the OS
/// text setting.
///
/// Measured on a device at 200%: with the wordmark scaling, the brand row
/// overflowed by 5.5 px once the trailing slot grew to a 48 dp control, and
/// once Phase 6 made the wordmark `Flexible` it truncated to "Raajj…" instead
/// — a brand name cut mid-word, which reads as a bug rather than as an
/// adaptation. Every other string in the header still scales.
void main() {
  /// The header as Explore mounts it: brand, a trailing slot, two actions.
  Widget header() => AppHeader.brand(
    // A realistic island pill. Wider than this and the row is genuinely
    // too full at any text scale, which would test the harness rather
    // than the wordmark.
    trailingSlot: const SizedBox(width: 90, height: 36),
    actions: [
      AppHeaderAction(
        icon: Icons.notifications_outlined,
        label: 'Alerts',
        onTap: () {},
      ),
      AppHeaderAction(
        icon: Icons.person_outline,
        label: 'Account',
        onTap: () {},
      ),
    ],
  );

  Future<double> wordmarkWidth(WidgetTester tester, double scale) async {
    await pumpScreen(
      tester,
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: header()),
      ),
    );
    return tester
        .getSize(
          find.descendant(
            of: find.bySemanticsLabel('RaajjePro'),
            matching: find.byType(RichText),
          ),
        )
        .width;
  }

  testWidgets('is the same width at 100% and at 200% text', (tester) async {
    final normal = await wordmarkWidth(tester, 1);
    final huge = await wordmarkWidth(tester, 2);
    expect(
      huge,
      closeTo(normal, 0.01),
      reason: 'the wordmark must not grow with the OS text setting',
    );
  });

  testWidgets('reads in full at 200% when the row has room for it', (
    tester,
  ) async {
    // No trailing slot: the shape where the wordmark's natural 76 dp fits.
    // Whether a *fuller* row truncates depends on packing Phase 7 will change
    // when it builds the real island selector, so this asserts the wordmark's
    // own behaviour rather than one arrangement's spare space.
    await pumpScreen(
      tester,
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: AppHeader.brand(
            actions: [
              AppHeaderAction(
                icon: Icons.person_outline,
                label: 'Account',
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );

    // An overflowing Row throws; a truncated wordmark does not, so both are
    // asserted.
    expect(tester.takeException(), isNull);

    final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.bySemanticsLabel('RaajjePro'),
        matching: find.byType(RichText),
      ),
    );
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: 'the brand name must read in full, not as "Raajj…"',
    );
  });

  testWidgets('the screen title still scales — only the wordmark is fixed', (
    tester,
  ) async {
    // The title's *box* fills the row at both scales, so measure the text it
    // paints: a scaled line box is taller.
    Future<double> titleHeight(double scale) async {
      await pumpScreen(
        tester,
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: const Scaffold(
            body: AppHeader.page(title: 'Account settings'),
          ),
        ),
      );
      return tester
          .renderObject<RenderParagraph>(
            find.descendant(
              of: find.byType(AppHeader),
              matching: find.text('Account settings'),
            ),
          )
          .textSize
          .height;
    }

    expect(await titleHeight(2), greaterThan(await titleHeight(1)));
  });
}
