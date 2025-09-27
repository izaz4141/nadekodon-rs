import 'package:flutter/material.dart';
import '../pages/home_page.dart';

const double railWidth = 72;

class NavigationRailSection extends StatelessWidget {
  const NavigationRailSection({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ValueListenableBuilder2<int, bool>(
      first: navIndexNotifier,
      second: isExpandedNotifier,
      builder: (context, selectedIndex, isExpanded, _) {
        return Container(
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: colors.inversePrimary, // separator color
                width: 1,              // separator thickness
              ),
            ),
          ),
          child: NavigationRail(
            minWidth: railWidth,
            extended: isExpanded,
            selectedIndex: selectedIndex == 0 ? 1 : selectedIndex,
            onDestinationSelected: (index) {
              _NavigationHandler.handleDestinationSelection(
                index, 
                context, 
                navIndexNotifier,
                isExpandedNotifier,
              );
            },
            // Only set labelType if not extended
            labelType: isExpanded ? null : NavigationRailLabelType.none,
            leading: const SizedBox(height: 8),
            unselectedLabelTextStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            selectedLabelTextStyle: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: colors.primary,
            ),
            destinations: [
              NavigationRailDestination(
                icon: Icon(
                  isExpanded ? Icons.arrow_back_ios_new : Icons.menu_rounded,
                ),
                label: const Text(
                  "Menu",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.download),
                label: Text("Downloads"),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text("Settings"),
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


class _NavigationHandler {
  static void handleDestinationSelection(
    int index, 
    BuildContext context, 
    ValueNotifier<int> selectedIndexNotifier,
    ValueNotifier<bool> isExpandedNotifier
  ) {
    selectedIndexNotifier.value = index == 0 ? selectedIndexNotifier.value : index;
    
    // Handle different destination actions
    switch (index) {
      case 0:
        isExpandedNotifier.value = !isExpandedNotifier.value;
        break;
    }
  }
}