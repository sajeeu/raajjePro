import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/theme/app_theme.dart';
import 'package:raajjepro/shared/shared.dart';

/// The product rules the shared widgets carry (root `CLAUDE.md` invariants,
/// `frontend/CLAUDE.md` → Design System). Each test asserts the rule, not
/// the implementation — a wrong implementation must fail it.
void main() {
  Widget host(Widget child, {bool reducedMotion = false}) => MaterialApp(
    theme: AppTheme.light(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Scaffold(body: Center(child: child)),
    ),
  );

  group('VerificationBadge — three tiers, never a bare "Verified"', () {
    testWidgets('tier none renders nothing at all', (tester) async {
      await tester.pumpWidget(
        host(const VerificationBadge(tier: VerificationTier.none)),
      );
      final box = tester.getSize(find.byType(VerificationBadge));
      expect(box, Size.zero);
      expect(find.byType(Text), findsNothing);
    });

    for (final (tier, words) in [
      (VerificationTier.bronze, 'ID checked by RaajjePro'),
      (VerificationTier.silver, 'ID checked, work verified'),
      (VerificationTier.gold, 'ID checked, registered trade'),
    ]) {
      testWidgets('${tier.name} carries its exact public copy', (tester) async {
        await tester.pumpWidget(
          host(VerificationBadge(tier: tier, size: VerificationBadgeSize.full)),
        );
        expect(find.text(words), findsOneWidget);
        expect(find.text('Verified'), findsNothing);
        expect(find.textContaining('Verified Provider'), findsNothing);
      });
    }

    testWidgets('the chip form never says "Verified" on its own', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const VerificationBadge(tier: VerificationTier.gold)),
      );
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
      expect(texts, isNot(contains('Verified')));
      expect(texts.join(' '), contains('Gold'));
    });

    test('meets() orders the tiers', () {
      expect(VerificationTier.gold.meets(VerificationTier.silver), isTrue);
      expect(VerificationTier.silver.meets(VerificationTier.gold), isFalse);
      expect(VerificationTier.none.meets(VerificationTier.bronze), isFalse);
      expect(VerificationTier.parse('gold'), VerificationTier.gold);
      expect(VerificationTier.parse('verified'), VerificationTier.none);
    });
  });

  group('StatusBadge — honest payment copy, always a label', () {
    test('the receipt step says what happened, not "verified"', () {
      expect(
        StatusBadge.labelFor(BadgeStatus.receiptConfirmed),
        'Provider confirmed receipt',
      );
      for (final s in BadgeStatus.values) {
        final label = StatusBadge.labelFor(s).toLowerCase();
        expect(label, isNot(contains('verified')), reason: s.name);
        expect(label, isNot(contains('paid ✓')), reason: s.name);
        expect(label.trim(), isNotEmpty, reason: s.name);
      }
    });

    test('offline queue reads as pending, never as sent', () {
      expect(
        StatusBadge.labelFor(BadgeStatus.pendingOffline),
        'Pending — sends on reconnect',
      );
    });

    testWidgets('renders its label as text, not colour alone', (tester) async {
      await tester.pumpWidget(host(const StatusBadge(BadgeStatus.confirmed)));
      expect(find.text('Confirmed'), findsOneWidget);
    });
  });

  group('AppButton — loading keeps the label and blocks taps', () {
    testWidgets('loading', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          AppButton.primary(
            label: 'Pick a time',
            onPressed: () => taps++,
            loading: true,
          ),
        ),
      );
      expect(find.text('Pick a time'), findsOneWidget);
      expect(find.byType(AppSpinner), findsOneWidget);
      await tester.tap(find.byType(AppButton));
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('disabled is announced disabled and has no tap action', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(const AppButton.primary(label: 'Pick a time', onPressed: null)),
      );
      final data = tester
          .getSemantics(find.byType(AppButton))
          .getSemanticsData();
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      handle.dispose();
    });
  });

  group('Copy the product has retired never appears in lib/ or test/', () {
    // Root CLAUDE.md: Round 44 renamed "Book instantly"; Round 23 removed the
    // emergency marker; Rounds 25–26 replaced three categories; there is no
    // SMS; a bare "Verified" is never rendered; no editorial provider labels.
    const forbidden = <String, String>{
      r'Book instantly': 'Round 44 — the slot affordance is "Pick a time"',
      r'Emergency available': 'Round 23 — no emergency marker on a card',
      r'\bGardening\b': 'Round 25 — Pest Control',
      r'\bComputer\b': 'Round 25 — Appliance Repair',
      r'\bEvents\b': 'Round 26 — Home Repairs',
      r'\bSMS\b': 'there is no SMS in this system',
      "['\\\"]Verified['\\\"]":
          'never a bare "Verified" — three tiers, own copy',
      r'Verified Provider': 'never a bare "Verified"',
      r'Payment verified': 'RaajjePro cannot see the transfer',
      r'Prone to cancel|Price hiking|Unreliable': '§1f — no editorial labels',
    };

    test('source scan', () {
      final hits = <String>[];
      for (final dir in [Directory('lib'), Directory('test')]) {
        for (final file in dir.listSync(recursive: true).whereType<File>()) {
          if (!file.path.endsWith('.dart')) continue;
          if (file.path.endsWith('design_rules_test.dart')) continue;
          final lines = file.readAsLinesSync();
          for (var i = 0; i < lines.length; i++) {
            // A comment may quote a retired rule to say it is retired; a
            // string in a widget may not.
            if (lines[i].trimLeft().startsWith('//') ||
                RegExp(r'Round \d+').hasMatch(lines[i])) {
              continue;
            }
            for (final e in forbidden.entries) {
              if (RegExp(e.key).hasMatch(lines[i])) {
                hits.add(
                  '${file.path}:${i + 1}: ${lines[i].trim()}\n'
                  '    → ${e.value}',
                );
              }
            }
          }
        }
      }
      expect(hits, isEmpty, reason: hits.join('\n'));
    });
  });

  group('Pressable — the 48 dp floor', () {
    testWidgets('a 20 dp child gets a 48 dp hit area', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          Pressable(
            onTap: () => taps++,
            semanticLabel: 'Tiny',
            builder: (_, _) => const SizedBox.square(dimension: 20),
          ),
        ),
      );
      final size = tester.getSize(find.byType(Pressable));
      expect(size.width, greaterThanOrEqualTo(AppSizes.touchTarget));
      expect(size.height, greaterThanOrEqualTo(AppSizes.touchTarget));

      // A tap 22 dp off the visual centre still lands.
      final centre = tester.getCenter(find.byType(Pressable));
      await tester.tapAt(centre + const Offset(22, 22));
      expect(taps, 1);
    });

    testWidgets('an icon-only control is labelled', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          SaveHeartToggle(
            saved: false,
            onChanged: (_) {},
            itemName: 'Wall painting',
          ),
        ),
      );
      expect(
        tester.getSemantics(find.byType(SaveHeartToggle)),
        matchesSemantics(
          label: 'Save Wall painting',
          hasToggledState: true,
          isToggled: false,
          hasTapAction: true,
          hasFocusAction: true,
          isEnabled: true,
          hasEnabledState: true,
          isFocusable: true,
        ),
      );
      handle.dispose();
    });
  });

  group('AppToggle — disabled says why', () {
    testWidgets('the reason renders and is spoken', (tester) async {
      final handle = tester.ensureSemantics();
      const reason =
          'Electrical emergencies need Gold verification. Yours is Silver.';
      await tester.pumpWidget(
        host(
          const AppToggle(
            value: false,
            onChanged: null,
            label: 'Emergency service',
            disabledReason: reason,
          ),
        ),
      );
      expect(find.text(reason), findsOneWidget);
      final node = tester.getSemantics(find.byType(AppToggle));
      expect(node.label, contains(reason));
      handle.dispose();
    });
  });

  group('StatMiniCard — no zero that reads worse than no metric', () {
    testWidgets('null value reads "No data yet"', (tester) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 120,
            child: StatMiniCard(
              icon: Icons.schedule,
              label: 'On time',
              value: null,
            ),
          ),
        ),
      );
      expect(find.text('No data yet'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(find.text('0%'), findsNothing);
    });
  });

  group('Motion — every primitive has a reduced-motion path', () {
    testWidgets('durations collapse to zero', (tester) async {
      late ResolvedMotion normal;
      late ResolvedMotion reduced;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (c) {
              normal = AppMotion.of(c);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpWidget(
        host(
          Builder(
            builder: (c) {
              reduced = AppMotion.of(c);
              return const SizedBox();
            },
          ),
          reducedMotion: true,
        ),
      );
      expect(normal.page, AppMotion.page);
      expect(normal.pressScale, AppMotion.pressScale);
      expect(reduced.page, Duration.zero);
      expect(reduced.sheet, Duration.zero);
      expect(reduced.pressScale, 1);
      expect(reduced.sheetSlide, 0);
    });

    testWidgets('skeleton and spinner stop ticking under reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SkeletonLoader.rows(count: 1),
              const AppSpinner(color: Colors.blue),
            ],
          ),
          reducedMotion: true,
        ),
      );
      // Would time out if either controller were still repeating.
      await tester.pumpAndSettle();
    });

    testWidgets('the page transition enters from the trailing edge', (
      tester,
    ) async {
      for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
        final controller = AnimationController(
          vsync: tester,
          duration: AppMotion.page,
        );
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            home: Directionality(
              textDirection: direction,
              child: Builder(
                builder: (context) =>
                    const AppPageTransitionsBuilder().buildTransitions<void>(
                      MaterialPageRoute(builder: (_) => const SizedBox()),
                      context,
                      controller,
                      kAlwaysDismissedAnimation,
                      const SizedBox.square(dimension: 10, key: Key('page')),
                    ),
              ),
            ),
          ),
        );
        // At t = 0 the page is displaced by the full slide, towards the
        // trailing edge: +x in LTR, −x in RTL.
        final at0 = tester.getTopLeft(find.byKey(const Key('page')));
        controller.value = 1;
        await tester.pump();
        final at1 = tester.getTopLeft(find.byKey(const Key('page')));
        final dx = at0.dx - at1.dx;
        expect(
          dx,
          closeTo(
            direction == TextDirection.ltr
                ? AppMotion.screenSlide
                : -AppMotion.screenSlide,
            0.01,
          ),
          reason: direction.name,
        );
      }
    });
  });

  group('Category accents resolve by seeded token', () {
    test('known token, unknown token', () {
      expect(
        CategoryAccents.resolve('emerald'),
        CategoryAccents.byToken[AccentToken.emerald],
      );
      expect(CategoryAccents.resolve('gardening'), CategoryAccents.fallback);
      expect(CategoryAccents.resolve(null), CategoryAccents.fallback);
      expect(CategoryAccents.byToken.length, 12);
    });
  });
}
