import 'package:flutter/material.dart';

/// Design tokens system inspired by shadcn/ui and Material Design 3
/// This provides a centralized place for all design constants used in the app
class DesignTokens {
  const DesignTokens._();

  // ---------------------------------------------------------------------------
  // Spacing tokens (8px base unit)
  // ---------------------------------------------------------------------------

  static const double xs = 4; // Extra small
  static const double sm = 8; // Small
  static const double md = 12; // Medium
  static const double lg = 16; // Large
  static const double xl = 24; // Extra large
  static const double xxl = 32; // 2x Extra large
  static const double xxxl = 48; // 3x Extra large

  // Common spacing combinations
  static const EdgeInsets paddingXs = EdgeInsets.all(xs);
  static const EdgeInsets paddingSm = EdgeInsets.all(sm);
  static const EdgeInsets paddingMd = EdgeInsets.all(md);
  static const EdgeInsets paddingLg = EdgeInsets.all(lg);
  static const EdgeInsets paddingXl = EdgeInsets.all(xl);
  static const EdgeInsets paddingXxl = EdgeInsets.all(xxl);
  static const EdgeInsets paddingXxxl = EdgeInsets.all(xxxl);

  // Padding variations
  static const EdgeInsets paddingHorizontalSm = EdgeInsets.symmetric(
    horizontal: sm,
  );
  static const EdgeInsets paddingHorizontalMd = EdgeInsets.symmetric(
    horizontal: md,
  );
  static const EdgeInsets paddingHorizontalLg = EdgeInsets.symmetric(
    horizontal: lg,
  );

  static const EdgeInsets paddingVerticalSm = EdgeInsets.symmetric(
    vertical: sm,
  );
  static const EdgeInsets paddingVerticalMd = EdgeInsets.symmetric(
    vertical: md,
  );
  static const EdgeInsets paddingVerticalLg = EdgeInsets.symmetric(
    vertical: lg,
  );

  // ---------------------------------------------------------------------------
  // Border radius tokens
  // ---------------------------------------------------------------------------

  static const double radiusNone = 0;
  static const double radiusSm = 4;
  static const double radiusMd = 8;
  static const double radiusLg = 12;
  static const double radiusXl = 16;
  static const double radiusXxl = 20;
  static const double radiusHero = 32;
  static const double contentMaxWidth = 1320;
  static const double portalSidebarWidth = 250;
  static const double portalHeaderHeight = 70;
  static const double radiusCircle = 9999;

  // BorderRadius presets
  static const BorderRadius borderRadiusSm = BorderRadius.all(
    Radius.circular(radiusSm),
  );
  static const BorderRadius borderRadiusMd = BorderRadius.all(
    Radius.circular(radiusMd),
  );
  static const BorderRadius borderRadiusLg = BorderRadius.all(
    Radius.circular(radiusLg),
  );
  static const BorderRadius borderRadiusXl = BorderRadius.all(
    Radius.circular(radiusXl),
  );
  static const BorderRadius borderRadiusXxl = BorderRadius.all(
    Radius.circular(radiusXxl),
  );
  static const BorderRadius borderRadiusCircle = BorderRadius.all(
    Radius.circular(radiusCircle),
  );

  // BorderRadius for specific corners
  static const BorderRadius borderRadiusTopLg = BorderRadius.only(
    topLeft: Radius.circular(radiusLg),
    topRight: Radius.circular(radiusLg),
  );

  static const BorderRadius borderRadiusBottomLg = BorderRadius.only(
    bottomLeft: Radius.circular(radiusLg),
    bottomRight: Radius.circular(radiusLg),
  );

  // ---------------------------------------------------------------------------
  // Typography tokens
  // ---------------------------------------------------------------------------

  static const double fontSizeXs = 10;
  static const double fontSizeSm = 12;
  static const double fontSizeMd = 14;
  static const double fontSizeLg = 16;
  static const double fontSizeXl = 20;
  static const double fontSizeXxl = 24;
  static const double fontSizeXxxl = 32;
  static const double fontSizeDisplay = 57;

  // Font weights
  static const int fontWeightThin = 100;
  static const int fontWeightExtraLight = 200;
  static const int fontWeightLight = 300;
  static const int fontWeightNormal = 400;
  static const int fontWeightMedium = 500;
  static const int fontWeightSemiBold = 600;
  static const int fontWeightBold = 700;
  static const int fontWeightExtraBold = 800;
  static const int fontWeightBlack = 900;

  // Line heights
  static const double lineHeightTight = 1.2;
  static const double lineHeightNormal = 1.5;
  static const double lineHeightRelaxed = 1.75;
  static const double lineHeightLoose = 2.0;

  // Letter spacing
  static const double letterSpacingTighter = -0.5;
  static const double letterSpacingTight = -0.25;
  static const double letterSpacingNormal = 0;
  static const double letterSpacingWide = 0.25;
  static const double letterSpacingWider = 0.5;
  static const double letterSpacingWidest = 1.0;

  // ---------------------------------------------------------------------------
  // Shadow tokens
  // ---------------------------------------------------------------------------

  static const List<BoxShadow> shadowNone = [];

  static const List<BoxShadow> shadowSm = [
    BoxShadow(color: Color(0x0A000000), blurRadius: 2, offset: Offset(0, 1)),
  ];

  static const List<BoxShadow> shadowMd = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 4, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> shadowLg = [
    BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 4)),
  ];

  static const List<BoxShadow> shadowXl = [
    BoxShadow(color: Color(0x19000000), blurRadius: 8, offset: Offset(0, 8)),
  ];

  static const List<BoxShadow> shadowXxl = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 16, offset: Offset(0, 12)),
  ];

  // Shadow presets for elevated surfaces
  static const List<BoxShadow> shadowElevated = shadowXl;
  static const List<BoxShadow> shadowDialog = shadowXxl;
  static const List<BoxShadow> shadowTooltip = shadowMd;

  // ---------------------------------------------------------------------------
  // Animation/Duration tokens
  // ---------------------------------------------------------------------------

  static const Duration durationFast = Duration(milliseconds: 100);
  static const Duration durationBase = Duration(milliseconds: 200);
  static const Duration durationSlow = Duration(milliseconds: 300);
  static const Duration durationSlower = Duration(milliseconds: 500);

  static const Curve curveSmoothOut = Curves.easeOut;
  static const Curve curveSmoothIn = Curves.easeIn;
  static const Curve curveSmoothInOut = Curves.easeInOut;
  static const Curve curveLinear = Curves.linear;

  // ---------------------------------------------------------------------------
  // Breakpoints for responsive design (Tailwind-inspired)
  // ---------------------------------------------------------------------------

  static const double breakpointXs = 320;
  static const double breakpointSm = 640;
  static const double breakpointMd = 768;
  static const double breakpointLg = 1024;
  static const double breakpointXl = 1280;
  static const double breakpointXxl = 1536;

  // ---------------------------------------------------------------------------
  // Component sizes
  // ---------------------------------------------------------------------------

  // Button sizes
  static const double buttonHeightXs = 28;
  static const double buttonHeightSm = 32;
  static const double buttonHeightMd = 40;
  static const double buttonHeightLg = 48;
  static const double buttonHeightXl = 56;

  // Icon sizes
  static const double iconSizeXs = 16;
  static const double iconSizeSm = 20;
  static const double iconSizeMd = 24;
  static const double iconSizeLg = 32;
  static const double iconSizeXl = 48;

  // Input field sizes
  static const double inputHeightSm = 32;
  static const double inputHeightMd = 40;
  static const double inputHeightLg = 48;

  // App bar height
  static const double appBarHeight = 56;
  static const double appBarHeightWithStatus = 56 + 25; // Plus status bar

  // Bottom navigation height
  static const double bottomNavHeight = 80;

  // ---------------------------------------------------------------------------
  // Border width tokens
  // ---------------------------------------------------------------------------

  static const double borderWidthNone = 0;
  static const double borderWidthThin = 0.5;
  static const double borderWidthBase = 1;
  static const double borderWidthMedium = 1.5;
  static const double borderWidthThick = 2;
  static const double borderWidthThicker = 3;

  // BorderSide presets
  static const BorderSide borderSideThin = BorderSide(width: borderWidthThin);
  static const BorderSide borderSideBase = BorderSide(width: borderWidthBase);
  static const BorderSide borderSideMedium = BorderSide(
    width: borderWidthMedium,
  );

  // ---------------------------------------------------------------------------
  // Z-index / Elevation tokens
  // ---------------------------------------------------------------------------

  static const double elevationNone = 0;
  static const double elevationSm = 1;
  static const double elevationMd = 2;
  static const double elevationLg = 4;
  static const double elevationXl = 8;
  static const double elevationXxl = 16;
  static const double elevationModal = 24;

  // Material elevation (z-index equivalent)
  static const int zIndexBase = 0;
  static const int zIndexDropdown = 1000;
  static const int zIndexSticky = 1020;
  static const int zIndexFixed = 1030;
  static const int zIndexBackdrop = 1040;
  static const int zIndexOffcanvas = 1050;
  static const int zIndexModal = 1060;
  static const int zIndexPopover = 1070;
  static const int zIndexTooltip = 1080;

  // ---------------------------------------------------------------------------
  // Opacity tokens
  // ---------------------------------------------------------------------------

  static const double opacityNone = 0.0;
  static const double opacityXs = 0.05;
  static const double opacitySm = 0.1;
  static const double opacityMd = 0.25;
  static const double opacityLg = 0.5;
  static const double opacityXl = 0.75;
  static const double opacityFull = 1.0;

  // Opacity for disabled states
  static const double opacityDisabled = 0.38;
  static const double opacityHover = 0.08;
  static const double opacityFocus = 0.12;
  static const double opacityActive = 0.16;

  // ---------------------------------------------------------------------------
  // Utility methods
  // ---------------------------------------------------------------------------

  /// Get responsive padding based on screen size
  static EdgeInsets responsivePadding(double width) {
    if (width < breakpointSm) return paddingSm;
    if (width < breakpointMd) return paddingMd;
    if (width < breakpointLg) return paddingLg;
    return paddingXl;
  }

  /// Get responsive font size based on screen size
  static double responsiveFontSize(
    double baseSize,
    double width, {
    double scaleSmall = 0.9,
    double scaleMedium = 1.0,
    double scaleLarge = 1.1,
  }) {
    if (width < breakpointSm) return baseSize * scaleSmall;
    if (width < breakpointMd) return baseSize * scaleMedium;
    return baseSize * scaleLarge;
  }

  /// Get responsive spacing based on screen size
  static double responsiveSpacing(
    double width, {
    double smallValue = sm,
    double mediumValue = md,
    double largeValue = lg,
  }) {
    if (width < breakpointSm) return smallValue;
    if (width < breakpointLg) return mediumValue;
    return largeValue;
  }

  /// Create a custom box shadow with parameters
  static List<BoxShadow> customShadow({
    Color color = const Color(0x1A000000),
    double blurRadius = 8,
    double spreadRadius = 0,
    Offset offset = const Offset(0, 2),
  }) {
    return [
      BoxShadow(
        color: color,
        blurRadius: blurRadius,
        spreadRadius: spreadRadius,
        offset: offset,
      ),
    ];
  }

  /// Create a custom border radius
  static BorderRadius customBorderRadius({
    double topLeft = 0,
    double topRight = 0,
    double bottomLeft = 0,
    double bottomRight = 0,
  }) {
    return BorderRadius.only(
      topLeft: Radius.circular(topLeft),
      topRight: Radius.circular(topRight),
      bottomLeft: Radius.circular(bottomLeft),
      bottomRight: Radius.circular(bottomRight),
    );
  }

  /// Create a custom padding
  static EdgeInsets customPadding({
    double top = 0,
    double right = 0,
    double bottom = 0,
    double left = 0,
  }) {
    return EdgeInsets.fromLTRB(left, top, right, bottom);
  }
}
