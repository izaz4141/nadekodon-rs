import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';

import 'theme/app_theme.dart';
import 'ui/pages/home_page.dart';

import 'package:rinf/rinf.dart';
import 'src/bindings/bindings.dart';

class NadekoDon extends StatefulWidget {
  const NadekoDon({super.key});

  @override
  State<NadekoDon> createState() => _NadekoDonState();
}


class _NadekoDonState extends State<NadekoDon> {
  /// This `AppLifecycleListener` is responsible for the
  /// graceful shutdown of the async runtime in Rust.
  /// If you don't care about
  /// properly dropping Rust objects before shutdown,
  /// creating this listener is not necessary.
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onExitRequested: () async {
        finalizeRust(); // This line shuts down the async Rust runtime.
        return AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final schemes = AppTheme.getColorSchemes(lightDynamic, darkDynamic);

        return MaterialApp(
          title: 'Nadeko~don',
          theme: AppTheme.buildTheme(schemes.light, context),
          darkTheme: AppTheme.buildTheme(schemes.dark, context),
          home: const HomePage(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}