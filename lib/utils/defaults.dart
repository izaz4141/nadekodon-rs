import 'package:flutter/material.dart';

class DefaultSettings {
  static late String downloadFolder;
  static const bool retreatToTray = true;
  static const int serverPort = 8080;
  static const double speedLimit = 0.0;
  static const int downloadThreads = 8;
  static const int concurrencyLimit = 3;
  static const int downloadTimeout = 30;
  static const int downloadRetries = 5;
  static const ThemeMode themeMode = ThemeMode.system;
  static const bool useDynamicColor = true;
  static const int customColor = 0xFFFF4081;
}
