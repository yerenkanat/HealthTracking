/// Text on an accent tint must use the `*Text` token, never the fill token.
///
/// The child map's freshness badge painted its label in `Palette.good` /
/// `Palette.blue` / `Palette.amber` on a 14 % tint of that same colour:
///
///   live    #17A97A on its own tint — 2.62:1
///   delayed #E08A00 on its own tint — 2.38:1
///   recent  #1F5FBF on its own tint — 4.96:1
///
/// 13 px bold needs 4.5:1. So the one claim that screen exists to make — how
/// current the child's position is — was illegible in exactly the two states
/// that matter, «she is fine» and «this is late». The blue middle state passed,
/// which is why nothing ever looked obviously broken.
///
/// This measures the ratio arithmetically rather than rendering a widget: the
/// framework's `textContrastGuideline` samples what is on screen and can be
/// satisfied by a label that happens to sit over an opaque parent, which is a
/// different question from whether the PAIRING is sound. The pairing is the
/// rule, and the rule is what regresses.
library;

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/ui/design_system.dart';
import 'package:fcs_app/ui/theme.dart';

/// WCAG relative luminance.
double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

/// `fg` over `bg`, both opaque.
double _ratio(Color fg, Color bg) {
  final a = _lum(fg), b = _lum(bg);
  final hi = math.max(a, b), lo = math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}

/// What a translucent tint actually looks like once painted on the surface
/// beneath it — the colour the eye compares the text against.
Color _over(Color tint, double alpha, Color surface) => Color.fromARGB(
      255,
      ((tint.r * alpha + surface.r * (1 - alpha)) * 255).round(),
      ((tint.g * alpha + surface.g * (1 - alpha)) * 255).round(),
      ((tint.b * alpha + surface.b * (1 - alpha)) * 255).round(),
    );

void main() {
  // The three states of the freshness badge, at the alphas the widget uses.
  final pairs = <String, (Color fill, Color text, double alpha)>{
    'live': (Palette.good, Ds.mintText, 0.14),
    'recent': (Palette.blue, Ds.blueText, 0.14),
    'delayed': (Palette.amber, Ds.amberText, 0.14),
    'dwell chip': (Palette.amber, Ds.amberText, 0.12),
  };

  group('a status label is readable on its own tint', () {
    for (final e in pairs.entries) {
      test('${e.key} clears 4.5:1', () {
        final (fill, text, alpha) = e.value;
        final bg = _over(fill, alpha, Palette.surface);
        final r = _ratio(text, bg);
        expect(r, greaterThanOrEqualTo(4.5),
            reason: '${e.key}: ${r.toStringAsFixed(2)}:1 — 13 px bold needs 4.5:1. '
                'Use the *Text token, not the fill.');
      });
    }

    test('the fill token itself would NOT clear it — this is why the rule exists', () {
      // Proof the test can fail: the exact code that shipped.
      for (final e in pairs.entries) {
        final (fill, _, alpha) = e.value;
        if (fill == Palette.blue) continue; // the one that passed by luck
        final r = _ratio(fill, _over(fill, alpha, Palette.surface));
        expect(r, lessThan(4.5),
            reason: '${e.key}: the fill colour now clears 4.5:1 on its own tint. '
                'If a token changed, re-derive this test rather than deleting it.');
      }
    });
  });
}
