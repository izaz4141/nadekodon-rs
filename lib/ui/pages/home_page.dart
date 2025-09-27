// lib/ui/pages/home_page.dart
import 'package:flutter/material.dart';
import '../widgets/window_controls.dart';
import '../widgets/app_drawer.dart';
import 'settings_page.dart';
import 'download_page.dart';

import 'package:nadekodon/src/bindings/bindings.dart';

/// Shared state for navigation index
final ValueNotifier<int> navIndexNotifier = ValueNotifier<int>(0);
/// Whether the mini nav is expanded
final ValueNotifier<bool> isExpandedNotifier = ValueNotifier<bool>(false);


class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Row(
            children: const [
              NavigationRailSection(),
              Expanded(child: _PageContent()),
            ],
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Material(
              type: MaterialType.transparency,
              child: WindowControls(),
            ),
          ),

        ],
      ),
    );
  }
}

/// Right-side content that switches based on selected nav index
class _PageContent extends StatelessWidget {
  const _PageContent();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: navIndexNotifier,
      builder: (context, selectedIndex, _) {
        switch (selectedIndex) {
          case 1:
            return const DownloadPage();
          case 2:
            return const SettingsPage();
          default:
            return const Center(child: Text("Downloads Page!"));
        }
      },
    );
  }
}