import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nadekodon/ui/theme/app_theme.dart';

import 'package:nadekodon/ui/pages/home_page.dart';
import 'package:nadekodon/ui/widgets/components/account_switcher.dart';

const double railWidth = 72;
const double sidebarWidth = 360.00;

/// Swipeable sidebar that lives in the layout Stack
class InteractiveSidebar extends StatefulWidget {
  const InteractiveSidebar({super.key});

  @override
  State<InteractiveSidebar> createState() => _InteractiveSidebarState();
}

class _InteractiveSidebarState extends State<InteractiveSidebar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;
  final FocusNode _focusNode = FocusNode();

  double _dragValue = 0;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(-1.0, 0),
      end: Offset.zero,
    ).animate(_ctrl);

    _fadeAnim = _ctrl;

    isExpandedNotifier.addListener(_onExpandedChanged);

    if (isExpandedNotifier.value) {
      _ctrl.value = 1.0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    isExpandedNotifier.removeListener(_onExpandedChanged);
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onExpandedChanged() {
    if (isExpandedNotifier.value) {
      if (_ctrl.value < 1.0) _ctrl.animateTo(1.0, curve: Curves.easeOutCubic);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    } else {
      if (_ctrl.value > 0.0) _ctrl.animateBack(0.0, curve: Curves.easeOutCubic);
      _focusNode.unfocus();
    }
  }

  void _handleDragStart(DragStartDetails details) {
    _dragValue = _ctrl.value;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final width =
        (sidebarWidth * AppTheme.widthScale(context)) + AppTheme.spaceLG;
    _dragValue += details.delta.dx / width;
    _ctrl.value = _dragValue.clamp(0.0, 1.0);
  }

  void _handleDragEnd(DragEndDetails details) {
    _dragValue = _ctrl.value;
    final velocity = details.primaryVelocity ?? 0;

    if (velocity > 500) {
      isExpandedNotifier.value = true;
      _ctrl.animateTo(1.0, curve: Curves.easeOutCubic);
    } else if (velocity < -500) {
      isExpandedNotifier.value = false;
      _ctrl.animateBack(0.0, curve: Curves.easeOutCubic);
    } else if (_ctrl.value > 0.5) {
      isExpandedNotifier.value = true;
      _ctrl.animateTo(1.0, curve: Curves.easeOutCubic);
    } else {
      isExpandedNotifier.value = false;
      _ctrl.animateBack(0.0, curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final width = sidebarWidth * AppTheme.widthScale(context);
    final sidebarTotalWidth = width + AppTheme.spaceLG * 2;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final isVisible = _ctrl.value > 0 || isExpandedNotifier.value;
        final screenWidth = MediaQuery.of(context).size.width;

        return Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: isVisible ? screenWidth : railWidth,
          child: PopScope(
            canPop: !isVisible,
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) return;
              if (isVisible) {
                isExpandedNotifier.value = false;
              }
            },
            child: Focus(
              focusNode: _focusNode,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  if (isVisible) {
                    isExpandedNotifier.value = false;
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: _handleDragStart,
                onHorizontalDragUpdate: _handleDragUpdate,
                onHorizontalDragEnd: _handleDragEnd,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Scrim
                    if (_ctrl.value > 0)
                      Positioned.fill(
                        child: GestureDetector(
                          onTap: () => isExpandedNotifier.value = false,
                          behavior: HitTestBehavior.opaque,
                          child: FadeTransition(
                            opacity: _fadeAnim,
                            child: Container(
                              color: colors.shadow.withAlpha(100),
                            ),
                          ),
                        ),
                      ),

                    // Sidebar
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: sidebarTotalWidth,
                      child: SlideTransition(
                        position: _slideAnim,
                        child: Container(
                          width: width,
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
                  ],
                ),
              ),
            ),
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
