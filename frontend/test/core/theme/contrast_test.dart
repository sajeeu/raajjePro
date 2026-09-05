import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raajjepro/core/theme/app_theme.dart';

/// WCAG 2.x relative luminance and contrast ratio.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// AA for body text. Large text (≥ 18.66px bold / 24px) may use 3:1, but no
/// role in [AppTypography] below `screenTitle` qualifies, so everything
/// text-shaped is held to 4.5.
const aaText = 4.5;

/// AA for non-text UI graphics (WCAG 1.4.11).
const aaGraphic = 3.0;

void main() {
  const c = AppColors.light();

  void expectText(String what, Color fg, Color bg) {
    final r = contrast(fg, bg);
    expect(
      r,
      greaterThanOrEqualTo(aaText),
      reason: '$what: ${r.toStringAsFixed(2)}:1 is below AA text 4.5:1',
    );
  }

  void expectGraphic(String what, Color fg, Color bg) {
    final r = contrast(fg, bg);
    expect(
      r,
      greaterThanOrEqualTo(aaGraphic),
      reason: '$what: ${r.toStringAsFixed(2)}:1 is below AA graphic 3:1',
    );
  }

  group('text roles on their surfaces', () {
    for (final (name, bg) in [
      ('surface', c.surface),
      ('background', c.background),
      ('surfaceMuted', c.surfaceMuted),
    ]) {
      test('ink, secondary, tertiary and placeholder on $name', () {
        expectText('ink on $name', c.ink, bg);
        expectText('textSecondary on $name', c.textSecondary, bg);
        expectText('textTertiary on $name', c.textTertiary, bg);
        expectText('placeholder on $name', c.placeholder, bg);
      });
    }

    test('primary and accent text', () {
      expectText('primary on surface', c.primary, c.surface);
      expectText('primaryPressed on surface', c.primaryPressed, c.surface);
      expectText('accentText on accentTint', c.accentText, c.accentTint);
      expectText(
        'accentText on accentTintPressed',
        c.accentText,
        c.accentTintPressed,
      );
      expectText('onPrimary on primary', c.onPrimary, c.primary);
      expectText('onPrimary on primaryPressed', c.onPrimary, c.primaryPressed);
    });

    test('the CTA gradient under a centred label', () {
      // A centred label on a wide button spans roughly the middle 40% of the
      // width, which on the 135° gradient line is t ≈ 0.3 … 0.7. The light
      // end beyond t = 0.3 is a decorative corner; the label never sits on it.
      final g = c.ctaGradient;
      Color at(double t) {
        final stops = g.stops!;
        for (var i = 1; i < stops.length; i++) {
          if (t <= stops[i]) {
            final f = (t - stops[i - 1]) / (stops[i] - stops[i - 1]);
            return Color.lerp(g.colors[i - 1], g.colors[i], f)!;
          }
        }
        return g.colors.last;
      }

      for (final t in [0.3, 0.4, 0.5, 0.6, 0.7, 1.0]) {
        expectText('onPrimary on gradient at t=$t', c.onPrimary, at(t));
      }
    });
  });

  group('semantic text — the amber-on-white case in particular', () {
    test('warning', () {
      expectText('warningText on surface', c.warningText, c.surface);
      expectText('warningText on warningTint', c.warningText, c.warningTint);
      // The icon amber is a graphic, not text.
      expectGraphic('warning on surface', c.warning, c.surface);
    });
    test('success', () {
      expectText('successText on surface', c.successText, c.surface);
      expectText('successText on successTint', c.successText, c.successTint);
      expectGraphic('success on surface', c.success, c.surface);
    });
    test('error', () {
      expectText('error on surface', c.error, c.surface);
      expectText('errorText on errorTint', c.errorText, c.errorTint);
      expectText('onError on error', c.onError, c.error);
      expectText('onError on errorPressed', c.onError, c.errorPressed);
    });
    test('neutral and guarantee pills', () {
      expectText('neutralText on neutralTint', c.neutralText, c.neutralTint);
      expectText(
        'guaranteeText on guaranteeTint',
        c.guaranteeText,
        c.guaranteeTint,
      );
      expectText('guaranteeText on surface', c.guaranteeText, c.surface);
    });
  });

  group('verification tiers', () {
    for (final (name, tier) in [
      ('bronze', c.bronze),
      ('silver', c.silver),
      ('gold', c.gold),
    ]) {
      test(name, () {
        expectText('$name tier name on fill', tier.text, tier.fill);
        expectText('$name words on fill', tier.words, tier.fill);
      });
    }
  });

  group('category accents', () {
    for (final entry in CategoryAccents.byToken.entries) {
      test(entry.key.name, () {
        expectGraphic(
          '${entry.key.name} icon on tint',
          entry.value.icon,
          entry.value.tint,
        );
        expectText(
          '${entry.key.name} text on surface',
          entry.value.text,
          c.surface,
        );
        expectText(
          '${entry.key.name} text on tint',
          entry.value.text,
          entry.value.tint,
        );
      });
    }
    test('fallback', () {
      expectText(
        'fallback text on tint',
        CategoryAccents.fallback.text,
        CategoryAccents.fallback.tint,
      );
    });
  });

  group('graphics', () {
    test('rating star strokes separate filled from empty', () {
      expectGraphic(
        'ratingStarStroke on surface',
        c.ratingStarStroke,
        c.surface,
      );
      expectGraphic('ratingStarEmpty on surface', c.ratingStarEmpty, c.surface);
    });
    test(
      'disabled text is documented as exempt, not accidentally relied on',
      () {
        // WCAG 1.4.3 exempts inactive components. This pins the value so a
        // future change cannot quietly promote it to a live-text role.
        expect(contrast(c.disabledText, c.surface), lessThan(aaText));
      },
    );
  });
}
