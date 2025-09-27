import 'package:flutter/material.dart';

class ColorUtils {
  static Color getReadableTextColor(Color bg) {
    final brightness = ThemeData.estimateBrightnessForColor(bg);
    return brightness == Brightness.dark ? Colors.white : Colors.black;
  }
}
