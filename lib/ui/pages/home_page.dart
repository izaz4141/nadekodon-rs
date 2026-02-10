import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:nadekodon/utils/platform_service.dart';
import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/ui/widgets/window_controls.dart';
import 'package:nadekodon/ui/widgets/app_drawer.dart';
import 'package:nadekodon/ui/pages/system_page.dart';
import 'package:nadekodon/ui/pages/settings_page.dart';
import 'package:nadekodon/ui/pages/download_page.dart';

/// Shared state for navigation index
final ValueNotifier<int> navIndexNotifier = ValueNotifier<int>(1);

/// Whether the mini nav is expanded
final ValueNotifier<bool> isExpandedNotifier = ValueNotifier<bool>(false);

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = AppTheme.isDesktop(context);

        return Stack(
          children: [
            Scaffold(
              extendBodyBehindAppBar: !isDesktop,
              appBar: isDesktop
                  ? null
                  : AppBar(
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      leading: IconButton(
                        icon: const Icon(Icons.menu),
                        onPressed: () {
                          isExpandedNotifier.value = true;
                        },
                      ),
                      title: ValueListenableBuilder<int>(
                        valueListenable: navIndexNotifier,
                        builder: (context, selectedIndex, _) {
                          String title;
                          switch (selectedIndex) {
                            case 1:
                              title = 'Downloads';
                              break;
                            case 2:
                              title = 'Settings';
                              break;
                            case 3:
                              title = 'System';
                              break;
                            default:
                              title = 'Downloads';
                          }
                          return Text(title, style: textTheme.titleLarge);
                        },
                      ),
                    ),
              body: Stack(
                children: [
                  Row(
                    children: [
                      if (isDesktop) const NavigationRailSection(),
                      const Expanded(child: _PageContent()),
                    ],
                  ),
                  // Always include interactive sidebar so it can respond to swipes and hamburger menu
                  const InteractiveSidebar(),
                ],
              ),
            ),
            if (!kIsWeb && PlatformService.isDesktop) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: kToolbarHeight,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: (details) {
                    PlatformService().startDragging();
                  },
                  onDoubleTap: () async {
                    if (await PlatformService().isMaximized()) {
                      await PlatformService().unmaximize();
                    } else {
                      await PlatformService().maximize();
                    }
                  },
                ),
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
          ],
        );
      },
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
          case 3:
            return const SystemPage();
          default:
            return const DownloadPage();
        }
      },
    );
  }
}
