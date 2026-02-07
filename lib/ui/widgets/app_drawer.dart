import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nadekodon/ui/theme/app_theme.dart';

import 'package:nadekodon/ui/pages/home_page.dart';
import 'package:nadekodon/ui/widgets/components/account_switcher.dart';

const double railWidth = 72;
const double sidebarWidth = 360.00;

/// Separate widget that handles sidebar overlay
/// This is always present (but invisible) so it can respond to isExpandedNotifier
class SidebarOverlayHandler extends StatefulWidget {
  const SidebarOverlayHandler({super.key});

  @override
  State<SidebarOverlayHandler> createState() => _SidebarOverlayHandlerState();
}

class _SidebarOverlayHandlerState extends State<SidebarOverlayHandler>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _overlayEntry;

  late final AnimationController _ctrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(-0.2, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);

    isExpandedNotifier.addListener(_onExpandedChanged);

    if (isExpandedNotifier.value == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showSidebar());
    }
  }

  @override
  void dispose() {
    isExpandedNotifier.removeListener(_onExpandedChanged);
    _hideSidebar(immediate: true);
    _ctrl.dispose();
    super.dispose();
  }

  void _onExpandedChanged() {
    if (isExpandedNotifier.value) {
      _showSidebar();
    } else {
      _hideSidebar();
    }
  }

  void _showSidebar() {
    if (_overlayEntry != null) return;
    final overlay = Overlay.of(context, rootOverlay: true);

    _overlayEntry = OverlayEntry(
      builder: (ctx) {
        final colors = Theme.of(context).colorScheme;

        return Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => isExpandedNotifier.value = false,
            child: Stack(
              children: [
                // Scrim with fade animation (no blur for performance)
                RepaintBoundary(
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: Container(color: colors.shadow.withAlpha(100)),
                  ),
                ),

                // Sidebar
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () {},
                    child: SlideTransition(
                      position: _slideAnim,
                      child: FadeTransition(
                        opacity: _fadeAnim,
                        child: RepaintBoundary(
                          child: Container(
                            width: sidebarWidth * AppTheme.widthScale(context),
                            margin: const EdgeInsets.all(AppTheme.spaceLG),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusLG * 1.2,
                              ),
                              border: Border.all(
                                color: colors.outlineVariant.withAlpha(128),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: colors.shadow.withAlpha(40),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: const Material(
                              type: MaterialType.transparency,
                              child: _SidebarContent(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    overlay.insert(_overlayEntry!);
    _ctrl.forward();
  }

  void _hideSidebar({bool immediate = false}) {
    if (_overlayEntry == null) return;

    if (immediate) {
      _overlayEntry?.remove();
      _overlayEntry = null;
      _ctrl.reset();
      return;
    }

    _ctrl.reverse().then((_) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Provide a thin strip on the left edge to detect swipes
    return ValueListenableBuilder<bool>(
      valueListenable: isExpandedNotifier,
      builder: (context, isExpanded, _) {
        if (isExpanded) return const SizedBox.shrink();

        return Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: railWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: (details) {
              if (details.primaryDelta! > 7) {
                isExpandedNotifier.value = true;
              }
            },
          ),
        );
      },
    );
  }
}

class _SidebarContent extends StatelessWidget {
  const _SidebarContent();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ValueListenableBuilder<int>(
      valueListenable: navIndexNotifier,
      builder: (context, selectedIndex, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            _SidebarHeader(colors: colors, textTheme: textTheme),
            const Divider(height: 1),
            const SizedBox(height: 4),
            _SidebarItem(
              index: 1,
              icon: Icons.download,
              label: "Downloads",
              selected: selectedIndex == 1,
            ),
            _SidebarItem(
              index: 2,
              icon: Icons.settings,
              label: "Settings",
              selected: selectedIndex == 2,
            ),
            _SidebarItem(
              index: 3,
              icon: Icons.monitor,
              label: "System",
              selected: selectedIndex == 3,
            ),
            const Spacer(),
            const Divider(height: 1),
            AccountSwitcher(
              onAccountSwitch: () => isExpandedNotifier.value = false,
            ),
          ],
        );
      },
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({required this.colors, required this.textTheme});

  final ColorScheme colors;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.spaceXL * AppTheme.spaceScale(context),
        vertical: AppTheme.spaceMD * AppTheme.spaceScale(context),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.chevron_left,
              size: AppTheme.iconLG * AppTheme.iconScale(context),
              color: colors.onSurfaceVariant,
            ),
            onPressed: () => isExpandedNotifier.value = false,
          ),
          const SizedBox(width: 4),
          Text(
            "Navigation",
            style: textTheme.titleLarge?.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: SvgPicture.asset(
                'assets/icons/nadeko-don-filled.svg',
                width: AppTheme.iconXL * AppTheme.iconScale(context),
                height: AppTheme.iconXL * AppTheme.iconScale(context),
                colorFilter: ColorFilter.mode(colors.primary, BlendMode.srcIn),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final int index;
  final IconData icon;
  final String label;
  final bool selected;

  const _SidebarItem({
    required this.index,
    required this.icon,
    required this.label,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final bg = selected
        ? colors.primaryContainer.withAlpha(204)
        : Colors.transparent;
    final fg = selected ? colors.primary : colors.onSurfaceVariant;

    return InkWell(
      onTap: () {
        navIndexNotifier.value = index;
        isExpandedNotifier.value = false;
      },
      borderRadius: BorderRadius.circular(AppTheme.radiusMD),
      hoverColor: colors.surfaceContainerHighest.withAlpha(16),
      splashColor: colors.primary.withAlpha(32),
      child: Container(
        margin: EdgeInsets.symmetric(
          horizontal: AppTheme.spaceMD * AppTheme.spaceScale(context),
          vertical: AppTheme.spaceXS,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: AppTheme.spaceLG * AppTheme.spaceScale(context),
          vertical: AppTheme.spaceMD * AppTheme.spaceScale(context),
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppTheme.radiusMD),
          border: Border.all(
            color: selected ? colors.primary.withAlpha(64) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: AppTheme.iconMD * AppTheme.iconScale(context),
              color: fg,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: textTheme.bodyMedium?.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NavigationRailSection extends StatelessWidget {
  const NavigationRailSection({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ValueListenableBuilder2<int, bool>(
      first: navIndexNotifier,
      second: isExpandedNotifier,
      builder: (context, selectedIndex, isExpanded, _) {
        return RepaintBoundary(
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: colors.surfaceContainer, width: 2),
              ),
            ),
            child: NavigationRail(
              minWidth: railWidth * AppTheme.widthScale(context),
              extended: false,
              selectedIndex: selectedIndex == 0 ? 1 : selectedIndex,
              onDestinationSelected: (index) {
                if (index == 0) {
                  isExpandedNotifier.value = !isExpandedNotifier.value;
                } else {
                  navIndexNotifier.value = index;
                  if (isExpandedNotifier.value) {
                    isExpandedNotifier.value = false;
                  }
                }
              },
              labelType: NavigationRailLabelType.none,
              unselectedLabelTextStyle: textTheme.titleMedium,
              selectedLabelTextStyle: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.primary,
              ),
              destinations: [
                NavigationRailDestination(
                  icon: Icon(
                    isExpanded ? Icons.arrow_back_ios_new : Icons.menu_rounded,
                    size: AppTheme.iconMD * AppTheme.iconScale(context),
                  ),
                  label: Text(" Menu", style: textTheme.titleLarge),
                ),
                NavigationRailDestination(
                  icon: Icon(
                    Icons.download,
                    size: AppTheme.iconMD * AppTheme.iconScale(context),
                  ),
                  label: const Text(" Downloads"),
                ),
                NavigationRailDestination(
                  icon: Icon(
                    Icons.settings,
                    size: AppTheme.iconMD * AppTheme.iconScale(context),
                  ),
                  label: const Text(" Settings"),
                ),
                NavigationRailDestination(
                  icon: Icon(
                    Icons.monitor,
                    size: AppTheme.iconMD * AppTheme.iconScale(context),
                  ),
                  label: const Text(" System"),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ValueListenableBuilder2<A, B> extends StatelessWidget {
  final ValueNotifier<A> first;
  final ValueNotifier<B> second;
  final Widget Function(BuildContext, A, B, Widget?) builder;

  const ValueListenableBuilder2({
    super.key,
    required this.first,
    required this.second,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<A>(
      valueListenable: first,
      builder: (context, a, _) {
        return ValueListenableBuilder<B>(
          valueListenable: second,
          builder: (context, b, child) => builder(context, a, b, child),
        );
      },
    );
  }
}
