import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';

const fallbackSeed = Colors.pinkAccent;

class AppTheme {
  static ({ColorScheme light, ColorScheme dark}) getColorSchemes(
      ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
    final light = lightDynamic?.harmonized() ??
        ColorScheme.fromSeed(seedColor: fallbackSeed, brightness: Brightness.light);
    final dark = darkDynamic?.harmonized() ??
        ColorScheme.fromSeed(seedColor: fallbackSeed, brightness: Brightness.dark);

    return (light: light, dark: dark);
  }
}
