import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/features/gallery/presentation/gallery_screen.dart';

/// Plan §Phase 1, Done when: "the gallery renders every widget; a11y
/// criteria verified … at 200% text scale; the gallery also renders
/// correctly under a forced RTL Directionality with no overlap or clipping".
///
/// This suite is the repeatable half of that verification. Under each of
/// LTR, RTL, 200% text and reduced motion it scrolls the whole gallery and,
/// at every stop, checks:
///
/// * no `RenderFlex` overflow (the framework throws; the test fails);
/// * no paragraph whose laid-out text is larger than the box it was given
///   — the clipping the plan names;
/// * every node a screen reader can tap has a label and is at least
///   48 × 48 dp;
/// * every image and icon-only control has a label.
///
/// The screen-reader pass on a device (TalkBack / VoiceOver) is the other
/// half and is done by hand — see `docs/decisions/08-phase-1-design-system.md`.
/// The gallery shows a spinner and a shimmer, which by design never settle,
/// so `pumpAndSettle` cannot be used here. Two frames: the first starts any
/// ticker (a ticker's first tick reports zero elapsed), the second advances
/// past the longest transition (`AppMotion.page`, 350 ms).
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  // A 412 × 915 phone at 3×, the frame every prototype was drawn in.
  Future<void> pumpGallery(
    WidgetTester tester, {
    bool rtl = false,
    bool bigText = false,
    bool reducedMotion = false,
  }) async {
    tester.view.physicalSize = const Size(412 * 3, 915 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const GalleryScreen()),
    );
    // The gallery's own switches are the real code path, so use them.
    if (rtl) await tester.tap(find.text('RTL'));
    if (bigText) await tester.tap(find.text('200% text'));
    if (reducedMotion) await tester.tap(find.text('Reduced motion'));
    await settle(tester);
  }

  /// Controls the semantics audit has actually inspected, across all stops.
  /// Asserted against a floor so a semantics restructure that merged every
  /// control into a parent could not make the audit pass by auditing nothing.
  var auditedControls = 0;

  /// Walks the semantics tree and returns every violation as a string.
  List<String> auditSemantics(WidgetTester tester) {
    final violations = <String>[];
    // One pipeline owner per view; the test has one view.
    SemanticsNode? root;
    tester.binding.rootPipelineOwner.visitChildren((owner) {
      root ??= owner.semanticsOwner?.rootSemanticsNode;
    });
    expect(root, isNotNull, reason: 'semantics not enabled');

    // Anything cut by the scroll viewport's edge reports a clipped rect;
    // every element is fully visible at some scroll stop, so partial ones
    // are skipped here. The viewport starts below the header, not at y = 0.
    // Semantics transforms resolve to physical pixels; scale to match.
    final dpr = tester.view.devicePixelRatio;
    final logical = tester.getRect(find.byType(Scrollable).first);
    final viewport = Rect.fromLTRB(
      logical.left * dpr,
      logical.top * dpr,
      logical.right * dpr,
      logical.bottom * dpr,
    );

    void visit(SemanticsNode node, Matrix4 parentTransform) {
      // A node merged into its parent is not presented on its own; the
      // parent's data already includes it.
      if (node.isMergedIntoParent) return;
      final transform = node.transform == null
          ? parentTransform
          : (parentTransform.clone()..multiply(node.transform!));
      final global = MatrixUtils.transformRect(transform, node.rect);
      final partial =
          global.top < viewport.top + 1 ||
          global.bottom > viewport.bottom - 1 ||
          global.left < viewport.left - 1 ||
          global.right > viewport.right + 1;
      final data = node.getSemanticsData();
      final flags = data.flagsCollection;
      final hidden = flags.isHidden;
      final tappable = data.hasAction(SemanticsAction.tap);
      final isControl =
          flags.isButton ||
          flags.isTextField ||
          flags.isToggled != Tristate.none;
      final label = data.label.trim().isNotEmpty
          ? data.label
          : (data.tooltip.isNotEmpty ? data.tooltip : data.value);

      if (!hidden && !partial && (tappable || isControl)) {
        auditedControls++;
        if (label.trim().isEmpty) {
          violations.add('unlabelled control at ${node.rect}');
        }
        // The rect is in the node's own coordinates; the tap-scale
        // transform is at most 0.98, hence the half-dp tolerance.
        final size = node.rect.size;
        if (size.width < 47.5 || size.height < 47.5) {
          violations.add(
            'tap target ${size.width.toStringAsFixed(1)} × '
            '${size.height.toStringAsFixed(1)} for "$label"',
          );
        }
      }
      if (!hidden && flags.isImage && label.isEmpty) {
        violations.add('unlabelled image at ${node.rect}');
      }
      node.visitChildren((child) {
        visit(child, transform);
        return true;
      });
    }

    visit(root!, Matrix4.identity());
    return violations;
  }

  /// Every laid-out paragraph must fit the box it was given.
  List<String> auditTextClipping(WidgetTester tester) {
    final violations = <String>[];
    for (final ro in tester.renderObjectList<RenderParagraph>(
      find.byType(RichText),
    )) {
      if (!ro.attached || ro.debugNeedsLayout) continue;
      final text = ro.textSize;
      final box = ro.size;
      if (text.width > box.width + 0.5 || text.height > box.height + 0.5) {
        violations.add(
          '"${ro.text.toPlainText().split('\n').first}" needs '
          '${text.width.toStringAsFixed(0)}×${text.height.toStringAsFixed(0)} '
          'but has ${box.width.toStringAsFixed(0)}×${box.height.toStringAsFixed(0)}',
        );
      }
    }
    return violations;
  }

  /// A word forced onto two lines is not clipped, so [auditTextClipping]
  /// cannot see it. Any paragraph that is a single word must lay out as one
  /// line — the case that bit was "Bookings" in a 70 dp nav slot at 200%.
  List<String> auditWordBreaks(WidgetTester tester) {
    final violations = <String>[];
    for (final ro in tester.renderObjectList<RenderParagraph>(
      find.byType(RichText),
    )) {
      if (!ro.attached || ro.debugNeedsLayout) continue;
      final text = ro.text.toPlainText().trim();
      if (text.isEmpty || text.contains(RegExp(r'\s'))) continue;
      final lineHeight = ro.getFullHeightForCaret(
        const TextPosition(offset: 0),
      );
      if (ro.textSize.height > lineHeight * 1.5) {
        violations.add('"$text" broke onto more than one line');
      }
    }
    return violations;
  }

  /// Scrolls to the end in view-height steps, auditing at each stop.
  Future<void> scrollAndAudit(WidgetTester tester, String scenario) async {
    final list = find.byType(ListView);
    final semantics = <String>{};
    final clipping = <String>{};
    auditedControls = 0;

    for (var step = 0; step < 40; step++) {
      semantics.addAll(auditSemantics(tester));
      clipping.addAll(auditTextClipping(tester));
      clipping.addAll(auditWordBreaks(tester));

      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      if (position.pixels >= position.maxScrollExtent - 1) break;
      await tester.drag(list, const Offset(0, -600));
      await settle(tester);
    }

    expect(
      semantics,
      isEmpty,
      reason: '[$scenario] semantics:\n  ${semantics.join('\n  ')}',
    );
    expect(
      clipping,
      isEmpty,
      reason: '[$scenario] text clipping:\n  ${clipping.join('\n  ')}',
    );
    // ~60 controls are in the gallery; well over that across the stops.
    expect(
      auditedControls,
      greaterThan(60),
      reason: '[$scenario] the semantics audit inspected too few controls',
    );
  }

  /// Opens the bottom sheet and audits it in place. The sheet is a route on
  /// the root navigator, so it is not covered by [scrollAndAudit].
  Future<void> openSheetAndAudit(WidgetTester tester, String scenario) async {
    await tester.scrollUntilVisible(
      find.text('Open a sheet'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Open a sheet'));
    await settle(tester);
    await tester.tap(find.text('Open a sheet'));
    await settle(tester);
    expect(find.text('Cancel this booking?'), findsOneWidget);

    final semantics = auditSemantics(tester);
    final clipping = [...auditTextClipping(tester), ...auditWordBreaks(tester)];
    expect(
      semantics,
      isEmpty,
      reason: '[$scenario sheet] semantics:\n  ${semantics.join('\n  ')}',
    );
    expect(
      clipping,
      isEmpty,
      reason: '[$scenario sheet] text clipping:\n  ${clipping.join('\n  ')}',
    );

    await tester.tap(find.text('Keep it'));
    await settle(tester);
    expect(find.text('Cancel this booking?'), findsNothing);
  }

  testWidgets('renders every section', (tester) async {
    await pumpGallery(tester);
    for (final title in [
      'Tokens',
      'Button',
      'Text input',
      'Toggle',
      'Chip',
      'Card',
      'Verification badge',
      'Status badge',
      'Stat mini card',
      'Rating stars',
      'Avatar',
      'Header',
      'Bottom navigation',
      'Save heart',
      'Empty · error · loading',
      'Bottom sheet',
    ]) {
      await tester.scrollUntilVisible(
        find.text(title),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(title), findsOneWidget, reason: 'section "$title"');
    }
  });

  testWidgets('LTR: labels, 48 dp targets, no clipping', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpGallery(tester);
    await scrollAndAudit(tester, 'LTR');
    await openSheetAndAudit(tester, 'LTR');
    handle.dispose();
  });

  testWidgets('RTL: labels, 48 dp targets, no clipping', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpGallery(tester, rtl: true);
    expect(
      Directionality.of(tester.element(find.text('Tokens'))),
      TextDirection.rtl,
    );
    await scrollAndAudit(tester, 'RTL');
    await openSheetAndAudit(tester, 'RTL');
    // The sheet really is under the RTL override, not just the gallery body.
    await tester.tap(find.text('Open a sheet'));
    await settle(tester);
    expect(
      Directionality.of(tester.element(find.text('Cancel this booking?'))),
      TextDirection.rtl,
    );
    await tester.tap(find.text('Keep it'));
    await settle(tester);
    handle.dispose();
  });

  testWidgets('200% text: labels, 48 dp targets, no clipping', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpGallery(tester, bigText: true);
    expect(
      MediaQuery.textScalerOf(tester.element(find.text('Tokens'))).scale(10),
      20,
    );
    await scrollAndAudit(tester, '200%');
    await openSheetAndAudit(tester, '200%');
    handle.dispose();
  });

  testWidgets('RTL at 200% text', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpGallery(tester, rtl: true, bigText: true);
    await scrollAndAudit(tester, 'RTL 200%');
    await openSheetAndAudit(tester, 'RTL 200%');
    handle.dispose();
  });

  testWidgets('reduced motion: renders and settles', (tester) async {
    await pumpGallery(tester, reducedMotion: true);
    expect(
      MediaQuery.disableAnimationsOf(tester.element(find.text('Tokens'))),
      isTrue,
    );
    // Skeletons and spinners must not keep the frame pump alive.
    await tester.scrollUntilVisible(
      find.text('Empty · error · loading'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: 'something is still animating under reduced motion',
    );
  });
}
