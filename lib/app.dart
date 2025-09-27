import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'theme/app_theme.dart';
import 'ui/pages/home_page.dart';

class NadekoDon extends StatelessWidget {
  const NadekoDon({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final schemes = AppTheme.getColorSchemes(lightDynamic, darkDynamic);

        return MaterialApp(
          title: 'Nadeko~don',
          theme: ThemeData(
            colorScheme: schemes.light,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: schemes.dark,
            useMaterial3: true,
          ),
          home: const HomePage(),
        );
      },
    );
  }
}
