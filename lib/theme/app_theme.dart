import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';

const fallbackSeed = Colors.pinkAccent;
const double kDesktopWidthBreakpoint = 640;

class AppTheme {
  static ({ColorScheme light, ColorScheme dark}) getColorSchemes(
    ColorScheme? lightDynamic,
    ColorScheme? darkDynamic, {
    required Color customSeed,
    required bool useDynamicColor,
  }) {
    ColorScheme? light;
    ColorScheme? dark;

    if (useDynamicColor && lightDynamic != null && darkDynamic != null) {
      light = lightDynamic.harmonized();
      dark = darkDynamic.harmonized();
    } else {
      light = ColorScheme.fromSeed(
        seedColor: customSeed,
        brightness: Brightness.light,
      );
      dark = ColorScheme.fromSeed(
        seedColor: customSeed,
        brightness: Brightness.dark,
      );
    }

    return (light: light, dark: dark);
  }

  // Base sizes (desktop defaults)
  static const double textXS = 8;
  static const double textSM = 12;
  static const double textMD = 16;
  static const double textLG = 24;
  static const double textXL = 32;
  static const double textXXL = 48;

  static const double spaceXS = 4;
  static const double spaceSM = 8;
  static const double spaceMD = 12;
  static const double spaceLG = 16;
  static const double spaceXL = 24;
  static const double spaceXXL = 32;

  static const double radiusSM = 8;
  static const double radiusMD = 12;
  static const double radiusLG = 24;

  static const double iconXS = 12;
  static const double iconSM = 16;
  static const double iconMD = 24;
  static const double iconLG = 32;
  static const double iconXL = 48;
  static const double iconXXL = 64;

  static const double dialogWidthDesktop = 620;
  static const double dialogWidthMobile = 480;
  static const double dialogMaxHeightDesktop = 420;
  static const double dialogMaxHeightMobile = 320;

  /// Determine if the layout is desktop-style
  static bool isDesktop(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= kDesktopWidthBreakpoint;
  }

  /// Responsive dialog width
  static double dialogWidth(BuildContext context) =>
      isDesktop(context) ? dialogWidthDesktop : dialogWidthMobile;

  /// Responsive dialog height
  static double dialogMaxHeight(BuildContext context) =>
      isDesktop(context) ? dialogMaxHeightDesktop : dialogMaxHeightMobile;

  static double textScale(BuildContext context) =>
      isDesktop(context) ? 1.0 : 0.95;
  static double spaceScale(BuildContext context) =>
      isDesktop(context) ? 1.0 : 0.95;
  static double iconScale(BuildContext context) =>
      isDesktop(context) ? 1.0 : 0.9;
  static double radiusScale(BuildContext context) =>
      isDesktop(context) ? 1.0 : 0.95;
  static double widthScale(BuildContext context) =>
      isDesktop(context) ? 1.0 : 0.8;
  static double heightScale(BuildContext context) =>
      isDesktop(context) ? 1.0 : 0.9;

  // =====================
  // THEME BUILDER
  // =====================
  static ThemeData buildTheme(ColorScheme scheme, BuildContext context) {
    final isDesktopLayout = isDesktop(context);

    // For smaller mobile screens, scale things down
    final textScale = isDesktopLayout ? 1.0 : 0.8;
    final spaceScale = isDesktopLayout ? 1.0 : 0.8;
    final radiusScale = isDesktopLayout ? 1.0 : 0.8;

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity(
        horizontal: -1.0 / spaceScale,
        vertical: -3.0 / spaceScale,
      ),

      textTheme: TextTheme(
        bodySmall: TextStyle(
          fontSize: textSM * textScale,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: TextStyle(
          fontSize: textMD * textScale,
          fontWeight: FontWeight.w400,
        ),
        bodyLarge: TextStyle(
          fontSize: textLG * textScale,
          fontWeight: FontWeight.w400,
        ),
        titleSmall: TextStyle(
          fontSize: textMD * textScale,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          fontSize: textLG * textScale,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(
          fontSize: textXL * textScale,
          fontWeight: FontWeight.w800,
        ),
      ),

      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMD * radiusScale),
        ),
        margin: EdgeInsets.symmetric(
          horizontal: spaceSM * spaceScale,
          vertical: spaceSM * spaceScale,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMD * radiusScale),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: spaceSM * spaceScale,
            vertical: spaceSM * spaceScale,
          ),
        ),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(radiusSM * radiusScale),
        ),
        textStyle: TextStyle(
          fontSize: textSM * textScale,
          color: scheme.onSurface,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: spaceSM * spaceScale,
          vertical: spaceXS * spaceScale,
        ),
        margin: EdgeInsets.all(spaceXS * spaceScale),
        waitDuration: const Duration(milliseconds: 200),
        showDuration: const Duration(seconds: 2),
        verticalOffset: spaceMD * spaceScale,
        preferBelow: false,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbVisibility: WidgetStateProperty.all(true),
        thickness: WidgetStateProperty.all(spaceXS * spaceScale),
        radius: Radius.circular(radiusSM * radiusScale),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return scheme.primary.withAlpha(200);
          }
          if (states.contains(WidgetState.hovered)) {
            return scheme.primary.withAlpha(150);
          }
          return scheme.onSurfaceVariant.withAlpha(100);
        }),
      ),
    );
  }
}
