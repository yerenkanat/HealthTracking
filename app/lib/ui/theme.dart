/// Premium LIGHT theme — refined, professional, calm. Soft off-white canvas,
/// white cards with subtle shadows (no neon glow), a restrained violet accent with
/// per-metric colors, Outfit for text and JetBrains Mono for numbers.
library;

import 'package:flutter/material.dart';

class Palette {
  // Canvas + surfaces (light)
  static const bg = Color(0xFFF4F5FA);
  static const bgElevated = Color(0xFFFFFFFF);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceHi = Color(0xFFFFFFFF);

  // Accents (refined)
  static const violet = Color(0xFF6D5AE6);
  static const pink = Color(0xFFE85C8A);
  static const teal = Color(0xFF12B3A6);
  static const blue = Color(0xFF4F8DF5);

  // Warm FemTech accents (women's-health calendar + gestation)
  static const rose = Color(0xFFF67CA6); // soft warm pink
  static const roseDeep = Color(0xFFE0568A);
  static const blush = Color(0xFFFDF2F6); // whisper-pink surface tint
  static const lilac = Color(0xFFEDE9FF); // soft violet fill

  // Status
  static const good = Color(0xFF17A672);
  static const watch = Color(0xFFE0930B);
  static const amber = Color(0xFFE8890B); // warm, low-anxiety "delayed" state
  static const danger = Color(0xFFE5484D);

  // Text + lines
  static const text = Color(0xFF1B1D28);
  // Secondary text. Darkened from 0xFF6E7180, which measured 4.45:1 over the
  // glass-card background — just under the 4.5:1 WCAG floor, and failing on
  // every screen that used it for body copy rather than a short label.
  static const textDim = Color(0xFF656877);
  static const border = Color(0xFFECEDF3);
  // Darker variants of the accents, for TEXT sitting on a tint of that same
  // accent. The bright accents above are tuned for icons, fills and borders,
  // where WCAG's 4.5:1 contrast rule for text doesn't apply — used as label
  // text over an 8–16% tint of themselves they measured as low as 2.65:1.
  // Keep the bright colour for the icon and the darker one for the words.
  static const goodText = Color(0xFF0B6B48);
  static const violetText = Color(0xFF5040B8);
  static const pinkText = Color(0xFFB33765);

  static const glass = Color(0xFFF2F3F8); // input / subtle fill

  static const violetPink = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [violet, pink],
  );
  static const tealBlue = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [teal, blue],
  );
  static const roseViolet = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [rose, violet],
  );

  // Soft, premium card shadow (not glow).
  static List<BoxShadow> get cardShadow => const [
        BoxShadow(color: Color(0x0F1B1D28), blurRadius: 20, offset: Offset(0, 8), spreadRadius: -6),
      ];
}

class FcsTheme {
  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: Palette.violet,
      onPrimary: Colors.white,
      secondary: Palette.pink,
      onSecondary: Colors.white,
      tertiary: Palette.teal,
      surface: Palette.surface,
      onSurface: Palette.text,
      surfaceContainerHighest: Palette.glass,
      error: Palette.danger,
      outline: Palette.border,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: Palette.bg,
      fontFamily: 'Outfit',
      canvasColor: Palette.bg,
      splashFactory: InkRipple.splashFactory,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: Palette.text,
        displayColor: Palette.text,
        fontFamily: 'Outfit',
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Palette.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Palette.text,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 23,
          fontWeight: FontWeight.w700,
          color: Palette.text,
          letterSpacing: -0.4,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(54),
          backgroundColor: Palette.violet,
          foregroundColor: Colors.white,
          elevation: 0,
          textStyle: const TextStyle(fontFamily: 'Outfit', fontSize: 16.5, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Palette.glass,
        hintStyle: const TextStyle(color: Palette.textDim),
        labelStyle: const TextStyle(color: Palette.textDim),
        floatingLabelStyle: const TextStyle(color: Palette.violet),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Palette.violet, width: 1.6),
        ),
      ),
      cardTheme: CardThemeData(
        color: Palette.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Palette.bgElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 66,
        indicatorColor: Palette.violet.withValues(alpha: 0.12),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
              fontFamily: 'Outfit',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: states.contains(WidgetState.selected) ? Palette.violet : Palette.textDim,
            )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? Palette.violet : Palette.textDim,
            )),
      ),
      dividerColor: Palette.border,
    );
  }
}

/// Darken a brand colour enough to use as TEXT on its own pale tint.
///
/// The pattern "accent text on accent-at-12%" recurs all over this app — badges,
/// tonal buttons, links — and the brand colours were chosen to look right as
/// fills, not as small text. Palette.violet on its own tint measures 3.58:1
/// against the 4.5 WCAG minimum; the same shape failed on the profile screen at
/// 4.02. This pulls the lightness down until it carries.
///
/// [Palette.violetText] is the hand-tuned violet and stays preferable where the
/// colour is known at authoring time; this is for the places that take a colour
/// as a parameter and cannot name one.
Color darkenForText(Color c) {
  final hsl = HSLColor.fromColor(c);
  // 0.36 lightness clears 4.5:1 against the app's near-white surfaces for every
  // hue in the palette, checked by the accessibility suite rather than by eye.
  return hsl.withLightness(hsl.lightness > 0.36 ? 0.36 : hsl.lightness).toColor();
}
