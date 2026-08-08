/// Ana-Bala design system — the canonical tokens.
///
/// Source of truth: `docs/CLAUDE-app-design.md`. Warm, soft, Android-first:
/// a cream screen, white cards on a 1px hairline, ONE soft shadow, and colour
/// used to say something rather than to decorate.
///
/// It replaced a neo-brutalist look — 2px ink outlines and hard offset shadows
/// with no blur. That is retired by name in the spec: at 130% system font the
/// outline and its shadow tear the card open, and on the cheap Android phones
/// this is sold to, a user who has enlarged her font is ordinary.
///
/// Red is reserved for SOS. Everything else that needs attention is amber.
///
/// `theme.dart` maps the app's older `Palette` names onto these values, so
/// screens that have not been converted yet still move to the new colours. New
/// code should reach for the tokens here.
///
/// ## Fonts, and why the rule is not cosmetic
///
/// The families are bundled (see pubspec.yaml) as VARIABLE fonts, so a weight is
/// only real if the style also carries `fontVariations`. Every helper below sets
/// both that and `fontWeight` — the latter still drives fallback matching.
///
/// Their Cyrillic coverage was read out of the actual `cmap` tables, not assumed:
///
/// | family        | Russian | Kazakh (ӘҒҚҢӨҰҮҺІ) |
/// |---------------|---------|--------------------|
/// | Unbounded     | full    | **missing ӘҒҚҢӨҰҮҺ** |
/// | Manrope       | full    | **missing ӘҒҚҢҰ**   |
/// | JetBrains Mono| full    | **missing ӘҒҚҢҰҺ**  |
/// | Rubik         | full    | full               |
///
/// Two consequences:
///
/// 1. On Kazakh screens the display face must be Rubik — Unbounded would drop
///    glyphs mid-word. [displayFamily] does this from the locale.
/// 2. Manrope cannot render Kazakh either, and Kazakh *names* (Айгерім, Нұрсұлтан)
///    appear inside the Russian interface all the time. So every style here also
///    carries `fontFamilyFallback: ['Rubik']` — without it those names render as
///    empty boxes on an otherwise Russian screen.
library;

import 'package:flutter/material.dart';
import '../l10n/l10n.dart';

// ---------------------------------------------------------------------------
// Colour
// ---------------------------------------------------------------------------

/// The palette from the spec, verbatim. Names match the CSS custom properties
/// so a screen can be read against the design doc line by line.
abstract final class Ds {
  /// Text. The single darkest value; no longer used for borders or shadows.
  static const ink = Color(0xFF241A22);

  /// Dark cards — the push / lock-screen view only.
  static const ink2 = Color(0xFF2C222C);

  /// Screen background.
  static const cream = Color(0xFFFBF6F3);

  /// Primary CTA, active tab, alerts.
  static const coral = Color(0xFFD6004A);

  /// Destructive actions and link text — the text-safe coral.
  static const coralDeep = Color(0xFFB8003F);

  /// Highlight blocks and secondary CTAs.
  static const yellow = Color(0xFFFFEA5C);

  /// Success, "child in the safe zone", the measuring screen.
  static const mint = Color(0xFF17A97A);

  /// Success as TEXT (the bright mint is a fill colour, not a text colour).
  static const mintDeep = Color(0xFF0E7A54);

  /// Info, the second child, SpO₂.
  static const blue = Color(0xFF1F5FBF);

  /// Warnings, battery, ratings.
  static const amber = Color(0xFFE08A00);

  // -- Text-safe accents ----------------------------------------------------
  //
  // The accents above (and the spec's own `mintDeep` / `coralDeep`) are tuned to
  // be seen as FILLS. Measured as small text they do not carry:
  //
  //   mintDeep  #0E9E6E   3.42:1 on white   3.23 on cream   2.95 on pastel mint
  //   coralDeep #E8264F   4.36:1 on white   4.11 on cream   3.38 on pastel pink
  //
  // All below the 4.5:1 WCAG AA floor for body text — the app's accessibility
  // suite fails on 40 screens with them. These variants keep the hue and
  // saturation exactly and lower only the lightness, until the ratio clears on
  // white, on cream AND on the accent's own pastel card. Use these whenever the
  // colour becomes WORDS; use the bright ones for fills, icons and borders.
  //
  // Ratios are white / cream / pastel.

  // -- Accent FILLS that carry white text ------------------------------------
  //
  // The mirror problem. White on the spec's coral `#FF3D71` measures **3.41:1**
  // — so the primary CTA, the most important control in the app, fails AA for
  // its own label. (Ink on coral is no better: 3.98.) Same for a mint or blue
  // fill with a white label.
  //
  // These are the same hues taken just dark enough that white clears 4.5:1.
  // Side by side with the spec swatch the difference is barely visible; in a
  // screenshot of a single button it is invisible. Use them wherever a solid
  // accent has white text ON it; use the bright ones for everything else.

  /// Primary CTA / FAB fill. White on it: 4.58:1.
  static const coralCta = Color(0xFFD6004A);

  /// Mint fill carrying WHITE text — the spec's darker green, not `#17A97A`.
  ///
  /// The spec lists `Норма #17A97A` as a fill and `#0E7A54` as its text colour.
  /// White on `#17A97A` measures **3.0:1**, so a green button with a white
  /// label would fail AA for its own text; the darker value carries it at
  /// 5.3:1. `Ds.mint` stays the bright one for indicators, dots and fills that
  /// hold DARK text.
  static const mintCta = Color(0xFF0E7A54);

  /// Blue fill carrying white text. 4.55:1.
  static const blueCta = Color(0xFF1F5FBF);

  /// Success text. Worst case 4.57:1.
  static const mintText = Color(0xFF0E7A54);

  /// Primary accent as text — links, destructive labels. Worst case 4.57:1.
  static const coralText = Color(0xFFB8003F);

  /// Info text. Worst case 4.51:1.
  static const blueText = Color(0xFF1F5FBF);

  /// Warning text. Worst case 4.55:1.
  static const amberText = Color(0xFF6E4200);

  // -- Pastel card fills. Small stat cards only; never a screen background. --
  static const pastelPink = Color(0xFFFFE4EA);
  static const pastelMint = Color(0xFFDFF3EA);
  static const pastelButter = Color(0xFFFFF0DC);
  static const pastelSky = Color(0xFFE2ECFF);
  static const pastelLilac = Color(0xFFEAE2FF);

  // -- Night theme (§2.17) ---------------------------------------------------
  //
  // «Тёмная тема только там, где ей место: таймер схваток, ночное кормление,
  // пуши на локскрине. Остальное — светлое.»
  //
  // These four are the whole palette. A woman timing contractions at 3am, or
  // feeding at 4, is holding a phone at arm's length in a dark room next to
  // someone asleep — the light theme in that moment is a torch in the face.

  /// The night canvas.
  static const nightBg = Color(0xFF171218);

  /// A card on it.
  static const nightSurface = Color(0xFF221A22);

  /// Body text on the night canvas. 12.9:1 on [nightBg].
  static const nightText = Color(0xFFF5EBF0);

  /// Secondary text — labels above the big numbers. 5.5:1 on [nightBg].
  static const nightTextDim = Color(0xFF9C8B96);

  /// The one action, in the bottom third. Deliberately a soft rose rather than
  /// the daytime coral: at night a saturated red IS the alarm colour, and this
  /// button is pressed every few minutes by someone who is not in danger.
  static const nightAction = Color(0xFFFF89A9);

  /// Text on [nightAction]. 8.6:1 — it has to be readable at a glance by
  /// someone mid-contraction.
  static const nightActionText = Color(0xFF3A0E1F);

  // -- Map placeholder stripes --
  static const mapStripeA = Color(0xFFE4EEE8);
  static const mapStripeB = Color(0xFFD5E4DC);

  // -- Text --
  /// Primary text. Same value as [ink] by design.
  static const text = ink;
  static const textBody = Color(0xFF4A3350);

  /// Secondary text — labels, captions, the right-hand value in a list row.
  ///
  /// The spec's value is `#8A7590`, which measures **3.94:1 on cream** and 4.18
  /// on white: below the 4.5:1 AA floor, and this is the most-used colour in the
  /// app (~416 call sites, mostly small labels). So the token carries the same
  /// hue darkened until it clears on every surface in the system — the spec's
  /// exact swatch is kept as [textSecondaryTint] for the places contrast rules
  /// do not cover.
  ///
  /// Worst measured ratio: 4.51.
  static const textSecondary = Color(0xFF5B4C57);

  /// The spec's literal secondary swatch. Icons, rules, decorative marks and
  /// text at ≥18pt bold (where the AA floor is 3:1) — never small body copy.
  static const textSecondaryTint = Color(0xFF7C6C77);

  /// Inactive tab labels and input placeholders. Same treatment: the spec's
  /// `#A895B3` is 2.9:1 on cream, which is unreadable for an 11px tab label.
  /// Worst measured ratio: 4.52.
  static const textMuted = Color(0xFF7C6C77);

  /// The spec's literal muted swatch, for non-text use.
  static const textMutedTint = Color(0xFFA8949F);

  /// Chevrons and other passive affordances.
  static const chevron = Color(0xFFC0AECB);

  /// Hairline between list rows, INSIDE a card — not between cards.
  static const divider = Color(0xFFF3EAE6);

  /// Card and input outline. Replaces the 2px ink border.
  static const hairline = Color(0xFFEADFD9);

  // -- On the dark push/lock screen --
  static const onDarkBody = Color(0xFFE4D3EC);
  static const onDarkSecondary = Color(0xFFCBB6D6);
  static const onDarkHairline = Color(0x2EFFFFFF); // rgba(255,255,255,.18)

  /// The one gradient in the system: the lock screen.
  static const lockScreenGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [ink2, ink, Color(0xFF1A0C22)],
  );

  /// Sticky tab bar / bottom action bar fill — cream at 94%, blurred behind.
  static const barFill = Color(0xF0FFF7F0);

  /// One accent dominates each screen (coral for home, mint for measuring,
  /// pink for onboarding); pastels appear only as small stat cards.
  static const accents = [coral, mint, blue, amber, yellow];
}

// ---------------------------------------------------------------------------
// Shape and elevation
// ---------------------------------------------------------------------------

abstract final class DsShape {
  /// Every card, input, chip, toggle, avatar and image carries this.
  /// A HAIRLINE, not an outline.
  ///
  /// This was 2px of ink on every surface — the signature of the old
  /// neo-brutalist look. docs/CLAUDE-app-design.md retires it in as many words:
  /// at 130% system font the outline plus its hard offset shadow tears the card
  /// open, and for an audience on cheap Android phones a user who has enlarged
  /// the font is ordinary, not an edge case.
  static const borderWidth = 1.0;
  static const border = BorderSide(color: Ds.hairline, width: borderWidth);

  /// The same outline as a whole [Border], usable in a `const BoxDecoration`.
  /// `Border.all(...)` is not a const constructor, so a decoration that was
  /// const stops being one the moment it gains an outline.
  static const inkBorder = Border.fromBorderSide(border);

  /// Empty / "add something here" states use a dashed ink border instead —
  /// see `DashedInkBorder` in `ds_widgets.dart`.
  static const radiusPill = 999.0;

  /// Inputs and list cards.
  static const radiusInput = 18.0;

  /// Content cards (22–26 in the spec; 24 is the default).
  static const radiusCard = 22.0;

  /// Icon tiles.
  static const radiusTile = 16.0;

  static BorderRadius get pill => BorderRadius.circular(radiusPill);
  static BorderRadius get input => BorderRadius.circular(radiusInput);
  static BorderRadius get card => BorderRadius.circular(radiusCard);
  static BorderRadius get tile => BorderRadius.circular(radiusTile);

  /// Hard offset shadow, **no blur** — the signature of this system. Applied to
  /// selected and primary elements only; most cards carry the border alone.
  ///
  /// The surface it sits under must be **opaque**. With no blur this is a solid
  /// ink rectangle drawn behind the box, so a translucent fill (an accent at
  /// 16%, say) lets the whole thing read through and the card turns near-black.
  /// Blend the tint against the canvas first — see [opaque].
  /// ONE soft shadow, replacing the hard offset one.
  ///
  /// Kept under the old name so every call site still reads; what it draws is
  /// now the spec's single elevation. A no-blur ink rectangle behind a card is
  /// what made the old system fall apart at large font sizes.
  static const List<BoxShadow> hardShadow = [
    BoxShadow(color: Color(0x0F3C1E2D), offset: Offset(0, 4), blurRadius: 14),
  ];

  /// Flatten a translucent tint onto the app canvas, so it can safely carry
  /// [hardShadow]. A no-op for colours that are already opaque.
  static Color opaque(Color c, [Color under = Ds.cream]) =>
      c.a >= 1.0 ? c : Color.alphaBlend(c, under);

  /// The smaller 5px variant used on the landing's large CTAs.
  /// The hero elevation — the one place a coloured shadow is allowed.
  static const List<BoxShadow> hardShadowLg = [
    BoxShadow(color: Color(0x47F4436B), offset: Offset(0, 14), blurRadius: 30),
  ];

  /// Nothing tappable is smaller than this.
  ///
  /// 48, not Apple's 44. The spec is iOS-first and 44 is the iOS floor, but the
  /// app ships to Android phones as its main audience, where the guideline —
  /// and docs/UI_REVIEW_CHECKLIST.md §4, which this project treats as
  /// mandatory — is 48. The two numbers disagreed and the code was quietly
  /// following the smaller one; 48 satisfies both.
  static const minTapTarget = 48.0;
}

/// Layout constants from the device frame section of the spec.
abstract final class DsLayout {
  /// Content starts below the status bar.
  static const screenPaddingTop = 62.0;

  /// Keep the home-indicator strip clear.
  static const homeIndicator = 34.0;

  static const screenPaddingH = 20.0;
  static const cardGap = 12.0;
}

// ---------------------------------------------------------------------------
// Type
// ---------------------------------------------------------------------------

abstract final class DsFont {
  static const display = 'Unbounded';
  static const displayKk = 'Rubik';
  static const body = 'Manrope';
  static const mono = 'JetBrainsMono';

  /// Rubik is the only bundled family with complete Kazakh coverage, so it
  /// backs every other family. See the table in the library doc.
  static const fallback = <String>[displayKk];

  /// Kazakh screens use Rubik for headings AND body; Unbounded would drop
  /// ә ғ қ ң ө ұ ү һ mid-word.
  static String displayFor(AppLocale locale) =>
      locale == AppLocale.kk ? displayKk : display;

  /// Manrope has no ә ғ қ ң ұ either, so Kazakh body text is Rubik as well.
  static String bodyFor(AppLocale locale) =>
      locale == AppLocale.kk ? displayKk : body;
}

/// Build a style on a variable font.
///
/// `fontVariations` is what actually moves the weight axis; `fontWeight` alone
/// would leave the font at its default instance and let the engine fake a bold.
/// Both are set: the latter still drives family and fallback matching.
TextStyle _v(
  String family, {
  required double size,
  required int weight,
  double? height,
  double? letterSpacing,
  Color color = Ds.text,
}) =>
    TextStyle(
      fontFamily: family,
      fontFamilyFallback: DsFont.fallback,
      fontSize: size,
      fontWeight: FontWeight.values[(weight ~/ 100) - 1],
      fontVariations: [FontVariation('wght', weight.toDouble())],
      height: height,
      letterSpacing: letterSpacing,
      color: color,
    );

/// The type scale, resolved for one locale.
///
/// Held as a [ThemeExtension] so it is built once per locale alongside the
/// theme and read with `context.ds` — that is what keeps the Kazakh font rule
/// automatic instead of something each screen has to remember.
@immutable
class DsTypography extends ThemeExtension<DsTypography> {
  DsTypography(this.locale)
      : _display = DsFont.displayFor(locale),
        _body = DsFont.bodyFor(locale);

  final AppLocale locale;
  final String _display;
  final String _body;

  /// Screen titles — 21–24.
  TextStyle get screenTitle => _v(_display,
      size: 23, weight: 800, height: 1.08, letterSpacing: -0.02 * 23);

  /// The one big number on a screen — 26–46.
  TextStyle heroMetric({double size = 46, Color color = Ds.text}) =>
      _v(_display,
          size: size,
          weight: 800,
          height: 1.05,
          letterSpacing: -0.02 * size,
          color: color);

  /// The number on a pastel stat tile.
  TextStyle statNumber({Color color = Ds.text}) => _v(_display,
      size: 26,
      weight: 700,
      height: 1.12,
      letterSpacing: -0.02 * 26,
      color: color);

  /// Card titles — 15–19.
  TextStyle get cardTitle => _v(_body, size: 17, weight: 800, height: 1.25);

  /// List-row labels.
  TextStyle get rowLabel => _v(_body, size: 15, weight: 700, height: 1.3);

  /// The value on the right of a list row.
  TextStyle get rowValue =>
      _v(_body, size: 15, weight: 600, height: 1.3, color: Ds.textSecondary);

  /// Body copy — 14–17.
  TextStyle body({double size = 15, Color color = Ds.textBody}) =>
      _v(_body, size: size, weight: 500, height: 1.45, color: color);

  /// Button and tab labels.
  TextStyle button({double size = 16, Color color = Colors.white}) =>
      _v(_body, size: size, weight: 800, height: 1.2, color: color);

  TextStyle caption({Color color = Ds.textSecondary}) =>
      _v(_body, size: 13, weight: 600, height: 1.35, color: color);

  /// Uppercase micro label — 11–12 with wide tracking. Always `.toUpperCase()`
  /// the string; the scale assumes it.
  /// [weight] is settable because the tab bar's two states differ by it: the
  /// spec sets the active label to 800 and the inactive one to 700, and with a
  /// single weight the only thing separating them was colour.
  TextStyle micro({Color color = Ds.textSecondary, double size = 11, int weight = 800}) =>
      _v(_body,
          size: size,
          weight: weight,
          height: 1.2,
          letterSpacing: 0.075 * size,
          color: color);

  /// Mono captions and placeholder text — 11–13.
  ///
  /// JetBrains Mono has no ә ғ қ ң ұ һ, so Kazakh falls through to Rubik and
  /// stops being monospaced. Use it for numbers and Latin placeholders.
  TextStyle mono({double size = 12, Color color = Ds.textSecondary}) =>
      _v(DsFont.mono, size: size, weight: 500, height: 1.3, color: color);

  /// The lock-screen clock.
  TextStyle get lockClock => _v(_display,
      size: 66,
      weight: 700,
      height: 1.0,
      letterSpacing: -0.02 * 66,
      color: Colors.white);

  @override
  DsTypography copyWith({AppLocale? locale}) =>
      DsTypography(locale ?? this.locale);

  /// Type does not tween — a half-way font is never a frame anyone wants.
  @override
  DsTypography lerp(ThemeExtension<DsTypography>? other, double t) =>
      t < 0.5 ? this : (other as DsTypography? ?? this);
}

/// `context.ds.cardTitle` — the short way to the scale above.
extension DsContext on BuildContext {
  DsTypography get ds =>
      Theme.of(this).extension<DsTypography>() ?? DsTypography(AppLocale.ru);
}
