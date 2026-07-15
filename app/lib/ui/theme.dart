/// Modern high-tech theme — dark, glassy, vibrant. Deep space background with
/// violet→pink→teal accents, bold Outfit type, JetBrains Mono for metric numbers.
/// Committed dark aesthetic (high-tech reads dark). Grounded in the ui-ux-pro-max
/// "glassmorphism + dark tech-dashboard" recommendation.
library;

import 'package:flutter/material.dart';

class Palette {
  // Space background layers
  static const bg = Color(0xFF0A0A14);
  static const bgElevated = Color(0xFF12121F);
  static const surface = Color(0xFF16162A);
  static const surfaceHi = Color(0xFF1E1E38);

  // Vibrant accents
  static const violet = Color(0xFF8B5CF6);
  static const pink = Color(0xFFEC4899);
  static const teal = Color(0xFF2DD4BF);
  static const blue = Color(0xFF60A5FA);

  // Status
  static const good = Color(0xFF34D399);
  static const watch = Color(0xFFFBBF24);
  static const danger = Color(0xFFFB5E6D);

  // Text
  static const text = Color(0xFFF5F5FA);
  static const textDim = Color(0xFF9BA0B5);
  static const border = Color(0x1AFFFFFF); // white 10%
  static const glass = Color(0x14FFFFFF); // white 8%

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
}

class FcsTheme {
  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: Palette.violet,
      onPrimary: Colors.white,
      secondary: Palette.pink,
      onSecondary: Colors.white,
      tertiary: Palette.teal,
      surface: Palette.surface,
      onSurface: Palette.text,
      surfaceContainerHighest: Palette.surfaceHi,
      error: Palette.danger,
      outline: Palette.border,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: Palette.bg,
      fontFamily: 'Outfit',
      canvasColor: Palette.bg,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: Palette.text,
        displayColor: Palette.text,
        fontFamily: 'Outfit',
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Palette.text,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Outfit',
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: Palette.text,
          letterSpacing: -0.5,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          backgroundColor: Palette.violet,
          foregroundColor: Colors.white,
          textStyle: const TextStyle(fontFamily: 'Outfit', fontSize: 17, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Palette.glass,
        hintStyle: const TextStyle(color: Palette.textDim),
        labelStyle: const TextStyle(color: Palette.textDim),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Palette.violet, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Palette.bgElevated,
        elevation: 0,
        height: 68,
        indicatorColor: Palette.violet.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontFamily: 'Outfit', fontSize: 12, fontWeight: FontWeight.w600, color: Palette.textDim),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected) ? Palette.violet : Palette.textDim,
            )),
      ),
      dividerColor: Palette.border,
    );
  }
}
