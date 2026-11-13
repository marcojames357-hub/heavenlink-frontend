import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'design_tokens.dart';

/// Haven Link design system.
///
/// Single source of truth for the brand palette:
///
/// Colours from the supplied Haven Link design.
class HavenTheme {
  const HavenTheme._();

  // ---------------------------------------------------------------------------
  // Brand palette
  // ---------------------------------------------------------------------------
  static const Color forest = Color(0xFF0B806B);
  static const Color darkTeal = Color(0xFF123B35);
  static const Color deepTeal = Color(0xFF14332E);
  static const Color gold = Color(0xFFEDAA2F);
  static const Color lightMint = Color(0xFFEDF7F3);
  static const Color veryLightMint = Color(0xFFF4F8F7);
  static const Color white = Colors.white;
  static const Color border = Color(0xFFDCE9E5);
  static const Color mintAccent = Color(0xFF72D9C2);

  /// Neutral secondary text colour with AA contrast on white and mint.
  static const Color muted = Color(0xFF718681);

  static const Color danger = Color(0xFFC0392B);

  static ShadThemeData get shadcn => ShadThemeData(
    colorScheme: const ShadColorScheme(
      background: veryLightMint,
      foreground: deepTeal,
      card: white,
      cardForeground: deepTeal,
      popover: white,
      popoverForeground: deepTeal,
      primary: forest,
      primaryForeground: white,
      secondary: lightMint,
      secondaryForeground: deepTeal,
      muted: Color(0xFFEDF4F2),
      mutedForeground: muted,
      accent: lightMint,
      accentForeground: deepTeal,
      destructive: danger,
      destructiveForeground: white,
      border: border,
      input: border,
      ring: forest,
      selection: mintAccent,
    ),
    radius: BorderRadius.circular(12),
  );

  // ---------------------------------------------------------------------------
  // Compatibility aliases for widgets that still use the teal/mint names.
  // ---------------------------------------------------------------------------
  static const Color teal = forest;
  static const Color mint = mintAccent;
  static const Color ink = deepTeal;
  static const Color ivory = veryLightMint;
  static const Color paper = white;

  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: forest,
      primary: forest,
      onPrimary: white,
      secondary: mintAccent,
      onSecondary: deepTeal,
      surface: white,
      onSurface: deepTeal,
      error: danger,
      onError: white,
    );

    final baseText = ThemeData.light().textTheme.apply(fontFamily: 'Inter');

    return FlexColorScheme.light(
      colorScheme: scheme,
      useMaterial3: true,
      surfaceMode: FlexSurfaceMode.level,
      blendLevel: 0,
    ).toTheme.copyWith(
      colorScheme: scheme,
      primaryTextTheme: baseText,
      scaffoldBackgroundColor: veryLightMint,
      textTheme: baseText.copyWith(
        headlineLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 34,
          fontWeight: FontWeight.w700,
          color: deepTeal,
          height: 1.15,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 27,
          fontWeight: FontWeight.w800,
          letterSpacing: -.8,
          color: deepTeal,
          height: 1.2,
        ),
        titleLarge: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: deepTeal,
        ),
        titleMedium: TextStyle(
          fontFamily: 'Inter',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: deepTeal,
        ),
        bodyLarge: TextStyle(
          fontFamily: 'Inter',
          color: deepTeal,
          height: 1.45,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Inter',
          color: deepTeal,
          height: 1.45,
        ),
        bodySmall: TextStyle(fontFamily: 'Inter', color: muted, height: 1.4),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: white,
        foregroundColor: deepTeal,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        toolbarHeight: 70,
        shape: const Border(bottom: BorderSide(color: border)),
      ),
      cardTheme: CardThemeData(
        color: paper,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
          side: const BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: paper,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        labelStyle: const TextStyle(fontFamily: 'Inter', color: muted),
        hintStyle: const TextStyle(
          fontFamily: 'Inter',
          color: Color(0x994C6B6E),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: forest, width: 1.6),
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
          backgroundColor: forest,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFB9C0B8),
          disabledForegroundColor: Colors.white70,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: forest,
          side: const BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: forest,
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: white,
        indicatorColor: lightMint,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? forest : muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? forest : muted,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: lightMint,
        side: const BorderSide(color: border),
        labelStyle: const TextStyle(
          fontFamily: 'Inter',
          color: deepTeal,
          fontSize: 13,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: deepTeal,
        contentTextStyle: TextStyle(fontFamily: 'Inter', color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: const WidgetStatePropertyAll(veryLightMint),
        headingTextStyle: TextStyle(
          fontFamily: 'Inter',
          color: muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        dataTextStyle: TextStyle(
          fontFamily: 'Inter',
          color: deepTeal,
          fontSize: 13,
        ),
        headingRowHeight: 48,
        dataRowMinHeight: 60,
        dataRowMaxHeight: 84,
        horizontalMargin: 20,
        columnSpacing: 28,
        dividerThickness: .6,
        decoration: BoxDecoration(
          color: white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
        iconColor: forest,
        collapsedIconColor: muted,
        childrenPadding: EdgeInsets.all(16),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: forest,
        foregroundColor: white,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: white,
        surfaceTintColor: Colors.transparent,
        width: 280,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: white,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: lightMint,
        headerForegroundColor: deepTeal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      dividerColor: const Color(0x24006B73),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: forest),
      listTileTheme: const ListTileThemeData(iconColor: forest),
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: TextStyle(
          fontFamily: 'Inter',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: deepTeal,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: paper,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? white : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? forest
              : const Color(0xFFB9C0B8),
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? forest : Colors.white,
        ),
        side: const BorderSide(color: muted, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: forest,
        unselectedLabelColor: muted,
        indicatorColor: forest,
        dividerColor: border,
        labelStyle: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: deepTeal,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Inter',
          color: Colors.white,
          fontSize: 12,
        ),
        waitDuration: const Duration(milliseconds: 400),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: paper,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: border),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStateProperty.all(paper),
          surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: lightMint,
          selectedForegroundColor: forest,
          foregroundColor: muted,
          side: const BorderSide(color: border),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: forest),
      ),
      scrollbarTheme: const ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(Color(0x660B806B)),
        radius: Radius.circular(8),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: forest,
        selectionHandleColor: forest,
        selectionColor: Color(0x330B806B),
      ),
      focusColor: const Color(0x1F0B806B),
      hoverColor: const Color(0x0F0B806B),
    );
  }
}
