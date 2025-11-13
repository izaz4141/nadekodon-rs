import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../theme/app_theme.dart';
import '../pages/home_page.dart';

const double railWidth = 72;
const double sidebarWidth = 360.00;

class NavigationRailSection extends StatefulWidget {
  const NavigationRailSection({super.key});

  @override
  State<NavigationRailSection> createState() => _NavigationRailSectionState();
}

class _NavigationRailSectionState extends State<NavigationRailSection>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _overlayEntry;
  PackageInfo _packageInfo = PackageInfo(
    appName: 'Unknown',
    packageName: 'Unknown',
    version: 'Unknown',
    buildNumber: 'Unknown',
  );

  late final AnimationController _ctrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _initPackageInfo();

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

  Future<void> _initPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _packageInfo = info;
    });
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
    if (overlay == null) return;

    _overlayEntry = OverlayEntry(
      builder: (ctx) {
        final colors = Theme.of(context).colorScheme;

        return Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => isExpandedNotifier.value = false,
            child: Stack(
              children: [
                // Slightly blurred scrim
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                  child: Container(
                    color: colors.shadow.withOpacity(0.25),
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
                        child: Container(
                          width: sidebarWidth * AppTheme.widthScale(context),
                          margin: const EdgeInsets.all(AppTheme.spaceLG),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusLG * 1.2),
                            border: Border.all(
                              color: colors.outlineVariant.withOpacity(0.5),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: colors.shadow.withOpacity(0.15),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Material(
                            type: MaterialType.transparency,
                            child: _buildSidebarContent(),
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

  Widget _buildSidebarContent() {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final selectedIndex = navIndexNotifier.value;

    Widget buildItem({
      required int index,
      required IconData icon,
      required String label,
    }) {
      final selected = selectedIndex == index;
      final bg = selected
          ? colors.primaryContainer.withOpacity(0.8)
          : Colors.transparent;
      final fg = selected ? colors.primary : colors.onSurfaceVariant;

      return InkWell(
        onTap: () {
          navIndexNotifier.value = index;
          isExpandedNotifier.value = false;
        },
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        hoverColor: colors.surfaceContainerHighest.withOpacity(0.08),
        splashColor: colors.primary.withOpacity(0.12),
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
              color: selected
                  ? colors.primary.withOpacity(0.3)
                  : Colors.transparent,
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
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final header = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppTheme.spaceXL * AppTheme.spaceScale(context),
        vertical: AppTheme.spaceMD * AppTheme.spaceScale(context),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left,
                size: AppTheme.iconLG * AppTheme.iconScale(context),
                color: colors.onSurfaceVariant),
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
                'assets/icons/nadeko-don-outlined.svg',
                width: AppTheme.iconXL * AppTheme.iconScale(context),
                height: AppTheme.iconXL * AppTheme.iconScale(context),
                colorFilter: ColorFilter.mode(
                  colors.primary,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        header,
        const Divider(height: 1),
        const SizedBox(height: 4),
        buildItem(index: 1, icon: Icons.download, label: "Downloads"),
        buildItem(index: 2, icon: Icons.settings, label: "Settings"),
        buildItem(index: 3, icon: Icons.monitor, label: "System"),
        const Spacer(),
        const Divider(height: 1),
        Padding(
          padding: EdgeInsets.all(AppTheme.spaceMD),
          child: Text(
            "v${_packageInfo.version}+${_packageInfo.buildNumber}",
            style: textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ValueListenableBuilder2<int, bool>(
      first: navIndexNotifier,
      second: isExpandedNotifier,
      builder: (context, selectedIndex, isExpanded, _) {
        return Container(
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: colors.surfaceContainer,
                width: 2,
              ),
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
                if (isExpandedNotifier.value) isExpandedNotifier.value = false;
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
                icon: Icon(Icons.download,
                    size: AppTheme.iconMD * AppTheme.iconScale(context)),
                label: const Text(" Downloads"),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings,
                    size: AppTheme.iconMD * AppTheme.iconScale(context)),
                label: const Text(" Settings"),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.monitor,
                    size: AppTheme.iconMD * AppTheme.iconScale(context)),
                label: const Text(" System"),
              ),
            ],
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
