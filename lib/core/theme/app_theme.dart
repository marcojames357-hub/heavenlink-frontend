import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Haven Link design system.
///
/// Single source of truth for the brand palette:
///
/// * primary teal blue [teal]          `#008C95` — primary actions, navigation
/// * dark teal [darkTeal]              `#006B73` — pressed / hover states
/// * deep teal [deepTeal]              `#00565D` — headings and strong text
/// * mint green [mint]                 `#6ED9C0`  — selected states, accents
/// * light mint [lightMint]            `#DDF7F0` — chips, banners, highlights
/// * very light mint [veryLightMint]   `#F1FCF9` — scaffold background
/// * white [paper]                     `#FFFFFF` — cards and surfaces
class HavenTheme {
  const HavenTheme._();

  // ---------------------------------------------------------------------------
  // Brand palette
  // ---------------------------------------------------------------------------
  static const Color teal = Color(0xFF008C95);
  static const Color darkTeal = Color(0xFF006B73);
  static const Color deepTeal = Color(0xFF00565D);
  static const Color mint = Color(0xFF6ED9C0);
  static const Color lightMint = Color(0xFFDDF7F0);
  static const Color veryLightMint = Color(0xFFF1FCF9);
  static const Color white = Color(0xFFFFFFFF);

  /// Neutral secondary text colour with AA contrast on white and mint.
  static const Color muted = Color(0xFF4C6B6E);

  static const Color danger = Color(0xFFC0392B);

  // ---------------------------------------------------------------------------
  // Legacy aliases
  //
  // Earlier screens were written against a placeholder forest/gold palette.
  // Keeping these names lets every existing screen inherit the Haven Link
  // teal/mint palette without a risky mechanical rename.
  // ---------------------------------------------------------------------------
  static const Color forest = teal;
  static const Color gold = mint;
  static const Color ink = deepTeal;
  static const Color ivory = veryLightMint;
  static const Color paper = white;

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: teal,
      primary: teal,
      onPrimary: white,
      secondary: mint,
      onSecondary: deepTeal,
      surface: white,
      onSurface: deepTeal,
      error: danger,
      onError: white,
    );

    final baseText = GoogleFonts.dmSansTextTheme();

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: veryLightMint,
      textTheme: baseText.copyWith(
        headlineLarge: GoogleFonts.dmSans(
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: deepTeal,
          height: 1.15,
        ),
        headlineMedium: GoogleFonts.dmSans(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: deepTeal,
          height: 1.2,
        ),
        titleLarge: GoogleFonts.dmSans(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: deepTeal,
        ),
        titleMedium: GoogleFonts.dmSans(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: deepTeal,
        ),
        bodyLarge: GoogleFonts.dmSans(color: deepTeal, height: 1.45),
        bodyMedium: GoogleFonts.dmSans(color: deepTeal, height: 1.45),
        bodySmall: GoogleFonts.dmSans(color: muted, height: 1.4),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: veryLightMint,
        foregroundColor: deepTeal,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: paper,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0x1F006B73)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: paper,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        labelStyle: const TextStyle(color: muted),
        hintStyle: const TextStyle(color: Color(0x994C6B6E)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0x33006B73)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0x33006B73)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: teal, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: danger, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: teal,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFA9C9CC),
          disabledForegroundColor: Colors.white70,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: teal,
          side: const BorderSide(color: Color(0x66008C95)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: teal,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: white,
        indicatorColor: lightMint,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? teal : muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? teal : muted,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: lightMint,
        side: const BorderSide(color: Color(0x33008C95)),
        labelStyle: const TextStyle(color: deepTeal, fontSize: 13),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: deepTeal,
        contentTextStyle: GoogleFonts.dmSans(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerColor: const Color(0x24006B73),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: teal),
      listTileTheme: const ListTileThemeData(iconColor: teal),
    );
  }
}
