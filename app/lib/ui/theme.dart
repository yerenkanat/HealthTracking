/// The app's Material theme, built from the Ana-Bala design system.
///
/// Tokens live in `design_system.dart` (`Ds`, `DsShape`, `DsTypography`) — that
/// file is the translation of `docs/design-system-app.md` and is what new code
/// should use.
///
/// ## Why `Palette` is still here
///
/// `Palette.violet`, `Palette.textDim` and friends appear ~1400 times across
/// 183 files. Renaming them all in one commit would be a diff nobody could
/// review, and would mix a mechanical rename with a visual change. So every
/// name is KEPT and re-pointed at its nearest design-system token: screens that
/// have not been converted yet move to the new palette on their own, and the
/// conversion becomes a series of small, readable commits instead of one large
/// one.
///
/// The names lie a little as a result — `Palette.violet` is coral now, exactly
/// as it was terracotta before this. Prefer `Ds.coral`. Each mapping below says
/// what it became.
library;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import 'design_system.dart';

class Palette {
  // ---- Canvas + surfaces ---------------------------------------------------
  /// Cream screen background.
  static const bg = Ds.cream;

  /// Cards sit on white inside the cream screen, outlined in ink.
  static const bgElevated = Colors.white;
  static const surface = Colors.white;
  static const surfaceHi = Colors.white;

  // ---- Accents -------------------------------------------------------------
  /// → the CTA coral. This name fills buttons, FABs and badges that carry WHITE
  /// text all over the app, and white on the spec's `#FF3D71` is only 3.41:1.
  /// [Ds.coral] itself stays available for fills whose text colour we control.
  static const violet = Ds.coralCta;

  /// → pastel pink. Was the gradient partner; now a card fill.
  static const pink = Ds.pastelPink;

  /// → mint. Success and "child is in the safe zone".
  static const teal = Ds.mint;

  /// → blue. Info, the second child, SpO₂.
  static const blue = Ds.blue;

  // ---- Women's-health accents ---------------------------------------------
  /// → coral. The cycle/gestation screens share the primary accent.
  static const rose = Ds.coral;

  /// → the measured text-safe coral. Mostly used for destructive and link TEXT,
  /// and the spec's own `coralDeep` only reaches 4.36:1 on white.
  static const roseDeep = Ds.coralText;

  /// → pastel pink surface tint.
  static const blush = Ds.pastelPink;

  /// → pastel lilac fill.
  static const lilac = Ds.pastelLilac;

  // ---- Status --------------------------------------------------------------
  static const good = Ds.mint;
  static const watch = Ds.amber;
  static const amber = Ds.amber;

  /// → the text-safe coral. `danger` labels error TEXT far more often than it
  /// fills anything, so it takes the measured variant.
  static const danger = Ds.coralText;

  // ---- Text + lines --------------------------------------------------------
  static const text = Ds.text;

  /// Secondary text — 4.9:1 on cream, above the 4.5:1 WCAG floor.
  static const textDim = Ds.textSecondary;

  /// NOTE: in this system a *card* border is 2px [Ds.ink]. This value is the
  /// hairline BETWEEN list rows. Reach for [DsShape.border] when outlining a
  /// surface, not for this.
  static const border = Ds.divider;

  /// Text sitting on a pale tint of the same accent needs the darker variant —
  /// the bright accents are tuned for fills. These are the MEASURED ones (see
  /// [Ds.mintText] and friends), not the spec's display-deep values, which fall
  /// under 4.5:1 on the very pastels they are paired with.
  static const goodText = Ds.mintText;
  static const violetText = Ds.coralText;
  static const pinkText = Ds.coralText;

  /// Input and other subtle fills.
  static const glass = Color(0xFFFDF0F5);

  // (The violetPink / tealBlue / roseViolet ramps are gone. The design system
  // has one gradient, on the lock screen; every call site now names a solid
  // accent, and keeping dead two-stop constants around invites their return.)

  /// → the hard offset shadow. No blur, no spread: that flat 4px step is the
  /// whole visual identity, and a soft shadow reads as a different product.
  static List<BoxShadow> get cardShadow => DsShape.hardShadow;
}

class FcsTheme {
  /// Build the theme for [locale].
  ///
  /// The locale is a real input, not a convenience: Unbounded has no Kazakh
  /// glyphs, so the display family has to change with the language or headings
  /// lose letters mid-word. Rebuild the theme when the language changes.
  static ThemeData light([AppLocale locale = AppLocale.ru]) {
    final type = DsTypography(locale);
    final bodyFamily = DsFont.bodyFor(locale);

    const scheme = ColorScheme.light(
      primary: Ds.coralCta,
      onPrimary: Colors.white,
      secondary: Ds.yellow,
      onSecondary: Ds.ink,
      tertiary: Ds.mint,
      surface: Colors.white,
      onSurface: Ds.ink,
      surfaceContainerHighest: Palette.glass,
      error: Ds.coralDeep,
      outline: Ds.ink,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: Ds.cream,
      fontFamily: bodyFamily,
      fontFamilyFallback: DsFont.fallback,
      canvasColor: Ds.cream,
      splashFactory: InkRipple.splashFactory,
    );

    return base.copyWith(
      extensions: [type],
      textTheme: base.textTheme
          .apply(bodyColor: Ds.text, displayColor: Ds.text, fontFamily: bodyFamily)
          .copyWith(
            // Headline slots take the display face so Material widgets pick up
            // Unbounded (or Rubik on Kazakh) without each screen asking.
            headlineLarge: type.heroMetric(size: 34),
            headlineMedium: type.screenTitle,
            headlineSmall: type.cardTitle,
            titleLarge: type.screenTitle,
            titleMedium: type.cardTitle,
            titleSmall: type.rowLabel,
            bodyLarge: type.body(size: 16),
            bodyMedium: type.body(),
            bodySmall: type.caption(),
            labelLarge: type.button(color: Ds.ink),
            labelSmall: type.micro(),
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: Ds.cream,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Ds.ink,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: type.screenTitle,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          backgroundColor: Ds.coralCta,
          foregroundColor: Colors.white,
          elevation: 0,
          textStyle: type.button(size: 17),
          // Pill + ink outline. A ButtonStyle cannot carry the hard offset
          // shadow, so a primary CTA that needs it wraps in `DsHardShadow`.
          shape: RoundedRectangleBorder(
            borderRadius: DsShape.pill,
            side: DsShape.border,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Ds.coralDeep,
          textStyle: type.button(color: Ds.coralDeep),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Ds.ink,
          minimumSize: const Size.fromHeight(54),
          side: DsShape.border,
          textStyle: type.button(color: Ds.ink),
          shape: RoundedRectangleBorder(borderRadius: DsShape.pill),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: type.body(color: Ds.textMuted),
        labelStyle: type.body(color: Ds.textSecondary),
        floatingLabelStyle: type.caption(color: Ds.coralDeep),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        border: OutlineInputBorder(borderRadius: DsShape.input, borderSide: DsShape.border),
        enabledBorder: OutlineInputBorder(borderRadius: DsShape.input, borderSide: DsShape.border),
        // Focus thickens the same ink line rather than recolouring it — the
        // outline is structural here, not decorative.
        focusedBorder: OutlineInputBorder(
          borderRadius: DsShape.input,
          borderSide: const BorderSide(color: Ds.ink, width: 3),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: DsShape.input,
          borderSide: const BorderSide(color: Ds.coralDeep, width: DsShape.borderWidth),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: DsShape.input,
          borderSide: const BorderSide(color: Ds.coralDeep, width: 3),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: DsShape.card,
          side: DsShape.border,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: Ds.ink,
        labelStyle: type.caption(color: Ds.ink),
        secondaryLabelStyle: type.caption(color: Colors.white),
        side: DsShape.border,
        shape: RoundedRectangleBorder(borderRadius: DsShape.pill),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Ds.mint : Ds.chevron,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Ds.ink),
        trackOutlineWidth: const WidgetStatePropertyAll(DsShape.borderWidth),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: DsShape.input,
          side: DsShape.border,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: type.cardTitle,
        contentTextStyle: type.body(),
        shape: RoundedRectangleBorder(
          borderRadius: DsShape.card,
          side: DsShape.border,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(DsShape.radiusCard)),
          side: DsShape.border,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Ds.barFill,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 66,
        // The active tab is named by colour and weight, not by a pill behind it.
        indicatorColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) {
            final selected = states.contains(WidgetState.selected);
            return type
                .micro(
                  size: 11,
                  // The spec's own colours are not used here: #FF3D71 and
                  // #A895B3 measure 3.6:1 and 2.9:1 on cream, and an 11px
                  // label needs 4.5:1. These are the darkened equivalents.
                  color: selected ? Ds.coralText : Ds.textMuted,
                  // 800 active / 700 inactive, per the spec. Weight is the
                  // second signal after colour, and it is the one that still
                  // works for a colour-blind reader.
                  weight: selected ? 800 : 700,
                )
                .copyWith(letterSpacing: 0);
          },
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            // 19 is the spec's glyph size, against an 11px label. It costs
            // nothing in reach: the tap target is the whole 66px-tall tab, not
            // the glyph, so this is legibility only — and the label carries the
            // meaning either way.
            size: 19,
            color: states.contains(WidgetState.selected) ? Ds.coral : Ds.textMuted,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(color: Ds.divider, thickness: 1, space: 1),
      dividerColor: Ds.divider,
    );
  }
}

/// WCAG contrast ratio between two opaque colours.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Darken a brand colour enough to use as TEXT on [on] (white by default).
///
/// The pattern "accent text on accent-at-12%" recurs all over this app — badges,
/// tonal buttons, links — and the brand colours are chosen to look right as
/// fills, not as small text.
///
/// This used to clamp lightness to 0.36 and claim that cleared 4.5:1 "for every
/// hue in the palette". That held for the old terracotta palette, whose hues are
/// all low-luminance, and quietly stopped holding when the design system brought
/// in bright greens and yellows: luminance is ~72% green-weighted, so mint at
/// lightness 0.36 still measures **2.57:1** on white — a failing colour returned
/// by the function whose whole job is to prevent one.
///
/// So it now *measures* instead of assuming, walking the lightness down until
/// the contrast actually clears. Slower, and correct for hues nobody has picked
/// yet.
///
/// Prefer the hand-tuned pairs where the colour is known when writing the code
/// ([Ds.coralDeep] for coral, [Ds.mintDeep] for mint). This is for the places
/// that take a colour as a parameter and cannot name one.
Color darkenForText(Color c, {Color on = Colors.white, double minRatio = 4.5}) {
  final hsl = HSLColor.fromColor(c);
  for (var l = hsl.lightness; l > 0; l -= 0.02) {
    final candidate = hsl.withLightness(l).toColor();
    if (contrastRatio(candidate, on) >= minRatio) return candidate;
  }
  // Black clears 4.5:1 against anything light enough to be a card.
  return hsl.withLightness(0).toColor();
}
