/// The design-system contract — mostly the font rule, because it is the part
/// that fails silently.
///
/// Unbounded, Manrope and JetBrains Mono have no ә ғ қ ң ұ. If a Kazakh string
/// reaches one of them with nothing behind it, the letters render as empty boxes
/// mid-word: the app still runs, nothing throws, no test that checks widget
/// structure notices, and the only signal is a screenshot nobody took. So the
/// rule is asserted here instead — see docs/design-system-app.md and the
/// coverage table in lib/ui/design_system.dart.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/l10n/l10n.dart';
import 'package:fcs_app/ui/design_system.dart';
import 'package:fcs_app/ui/theme.dart';

/// Every Kazakh-specific letter the bundled display/body faces lack.
const kazakhOnly = 'ӘҒҚҢӨҰҮҺІәғқңөұүһі';

void main() {
  group('the Kazakh font rule', () {
    test('Kazakh screens use Rubik for headings — Unbounded has no ә ғ қ ң', () {
      expect(DsFont.displayFor(AppLocale.kk), 'Rubik');
      expect(DsFont.displayFor(AppLocale.ru), 'Unbounded');
    });

    test('Kazakh body copy is Rubik too — Manrope has no ә ғ қ ң ұ either', () {
      // This is the one most easily got wrong: the spec says "Kazakh headings",
      // and it is tempting to leave body text on Manrope.
      expect(DsFont.bodyFor(AppLocale.kk), 'Rubik');
      expect(DsFont.bodyFor(AppLocale.ru), 'Manrope');
    });

    test('every style falls back to Rubik, so a Kazakh name survives the Russian UI', () {
      // Айгерім and Нұрсұлтан appear on Russian screens constantly. Without the
      // fallback, the і and ұ come out as boxes.
      final ru = DsTypography(AppLocale.ru);
      final styles = <String, TextStyle>{
        'screenTitle': ru.screenTitle,
        'heroMetric': ru.heroMetric(),
        'statNumber': ru.statNumber(),
        'cardTitle': ru.cardTitle,
        'rowLabel': ru.rowLabel,
        'rowValue': ru.rowValue,
        'body': ru.body(),
        'button': ru.button(),
        'caption': ru.caption(),
        'micro': ru.micro(),
        'mono': ru.mono(),
        'lockClock': ru.lockClock,
      };
      for (final e in styles.entries) {
        expect(
          e.value.fontFamilyFallback,
          contains('Rubik'),
          reason: '${e.key} has no Kazakh fallback — Kazakh names will show as boxes',
        );
      }
    });

    testWidgets('switching to Kazakh actually changes the rendered heading font', (tester) async {
      Future<String?> headingFamilyFor(AppLocale locale) async {
        await tester.pumpWidget(MaterialApp(
          theme: FcsTheme.light(locale),
          home: Builder(
            builder: (context) => Scaffold(
              body: Text('Денсаулық', style: context.ds.screenTitle),
            ),
          ),
        ));
        // MaterialApp puts an AnimatedTheme in the tree, so a theme swap is a
        // ~200ms transition, not an instant one. On the first frame the lerp is
        // still at t≈0 and hands back the OUTGOING typography — settle, or this
        // reads the previous locale's font and the assertion means nothing.
        await tester.pumpAndSettle();
        return tester.widget<Text>(find.byType(Text)).style?.fontFamily;
      }

      expect(await headingFamilyFor(AppLocale.ru), 'Unbounded');
      expect(await headingFamilyFor(AppLocale.kk), 'Rubik');
    });

    test('typography snaps rather than blending mid-transition', () {
      // There is no meaningful half-way point between two typefaces, so the
      // extension flips at the midpoint of the theme animation instead of
      // trying to interpolate. Asserted because the alternative — a frame
      // rendered in a font that is neither — is the kind of thing that only
      // shows up in a screenshot.
      final ru = DsTypography(AppLocale.ru);
      final kk = DsTypography(AppLocale.kk);
      expect(ru.lerp(kk, 0.0).locale, AppLocale.ru);
      expect(ru.lerp(kk, 0.49).locale, AppLocale.ru);
      expect(ru.lerp(kk, 0.5).locale, AppLocale.kk);
      expect(ru.lerp(kk, 1.0).locale, AppLocale.kk);
    });

    test('the Kazakh alphabet is spelled out so the coverage claim is checkable', () {
      // Guards the constant itself: if someone trims this list, the reason the
      // font rule exists stops being legible.
      for (final c in ['ә', 'ғ', 'қ', 'ң', 'ұ', 'ө', 'ү', 'һ', 'і']) {
        expect(kazakhOnly, contains(c));
      }
    });
  });

  group('variable fonts carry a real weight', () {
    test('styles set fontVariations, not just fontWeight', () {
      // The families are variable fonts declared once in pubspec. fontWeight
      // alone leaves them at their default instance and lets the engine fake a
      // bold; the wght axis only moves via fontVariations.
      final t = DsTypography(AppLocale.ru);
      for (final s in [t.screenTitle, t.cardTitle, t.body(), t.button(), t.micro()]) {
        expect(s.fontVariations, isNotNull);
        expect(s.fontVariations!.any((v) => v.axis == 'wght'), isTrue);
      }
    });

    test('the wght axis agrees with fontWeight', () {
      final t = DsTypography(AppLocale.ru);
      final title = t.screenTitle;
      final wght = title.fontVariations!.firstWhere((v) => v.axis == 'wght').value;
      expect(wght, 800);
      expect(title.fontWeight, FontWeight.w800);
    });
  });

  group('the shape language', () {
    test('borders are 2px ink', () {
      expect(DsShape.border.width, 2.0);
      expect(DsShape.border.color, Ds.ink);
    });

    test('the shadow is a hard offset with no blur', () {
      // A blurred shadow reads as a different product entirely.
      expect(DsShape.hardShadow.single.blurRadius, 0);
      expect(DsShape.hardShadow.single.offset, const Offset(4, 4));
      expect(DsShape.hardShadow.single.color, Ds.ink);
    });

    test('tap targets clear the 44px floor', () {
      expect(DsShape.minTapTarget, greaterThanOrEqualTo(44.0));
    });
  });

  group('the legacy Palette still resolves', () {
    // ~1400 call sites across 183 files read these. They are re-pointed at the
    // new tokens rather than renamed, so unconverted screens move to the new
    // palette on their own — but only while every name still exists.
    test('names map onto design-system tokens', () {
      expect(Palette.bg, Ds.cream);
      expect(Palette.text, Ds.ink);
      expect(Palette.good, Ds.mint);
      expect(Palette.cardShadow, DsShape.hardShadow);
      // The two accents that carry text or sit under white text take the
      // measured variants, not the spec swatches — see the Ds doc comments.
      expect(Palette.violet, Ds.coralCta); // fills, usually with a white label
      expect(Palette.danger, Ds.coralText); // almost always words
    });

    test('the accent names that render text are all contrast-safe', () {
      // Guards the whole class of regression: pointing one of these back at a
      // bright swatch turns 40 accessibility tests red, and nothing else.
      for (final c in [Palette.danger, Palette.roseDeep, Palette.goodText, Palette.violetText, Palette.pinkText]) {
        expect(contrastRatio(c, Colors.white), greaterThanOrEqualTo(4.5));
        expect(contrastRatio(c, Ds.cream), greaterThanOrEqualTo(4.5));
      }
      // And the fills that carry a white label.
      for (final fill in [Palette.violet, Ds.coralCta, Ds.mintCta, Ds.blueCta]) {
        expect(contrastRatio(Colors.white, fill), greaterThanOrEqualTo(4.5));
      }
    });

    test('accent-on-tint text colours stay legible', () {
      // darkenForText exists for the places that receive a colour at runtime and
      // must print words in it. Assert the thing that actually matters — the
      // contrast ratio against the white cards these sit on — rather than the
      // lightness value it happens to use to get there.
      double luminance(Color c) => c.computeLuminance();
      double ratio(Color fg, Color bg) {
        final a = luminance(fg), b = luminance(bg);
        final hi = a > b ? a : b, lo = a > b ? b : a;
        return (hi + 0.05) / (lo + 0.05);
      }

      for (final c in [Ds.coral, Ds.mint, Ds.blue, Ds.amber, Ds.yellow]) {
        expect(
          ratio(darkenForText(c), Colors.white),
          greaterThanOrEqualTo(4.5),
          reason: 'darkened ${c.toString()} fails WCAG AA as body text on white',
        );
      }
    });
  });

  group('the theme is wired to the tokens', () {
    testWidgets('scaffold, cards and inputs carry the system', (tester) async {
      final theme = FcsTheme.light(AppLocale.ru);
      expect(theme.scaffoldBackgroundColor, Ds.cream);
      // primary fills buttons that print white labels, so it is the CTA coral.
      expect(theme.colorScheme.primary, Ds.coralCta);

      // Cards are outlined, not shadowed.
      final cardShape = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(cardShape.side.width, DsShape.borderWidth);
      expect(cardShape.side.color, Ds.ink);
      expect(theme.cardTheme.elevation, 0);

      // The typography extension travels with the theme, which is what makes
      // `context.ds` locale-correct.
      expect(theme.extension<DsTypography>()?.locale, AppLocale.ru);
      expect(FcsTheme.light(AppLocale.kk).extension<DsTypography>()?.locale, AppLocale.kk);
    });

    testWidgets('context.ds falls back safely outside a themed subtree', (tester) async {
      // A widget rendered without the extension should still get a usable scale
      // rather than throwing.
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.light(),
        home: Builder(builder: (context) => Text('x', style: context.ds.body())),
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
