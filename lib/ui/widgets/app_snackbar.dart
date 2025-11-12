// lib/ui/widgets/app_snackbar.dart
import 'dart:async';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

enum SnackType { success, error, info }

class AppSnackBar {
  /// Show a top-floating snack that is inserted into the root overlay
  /// so it appears above dialogs and other modal routes.
  static void show(
    BuildContext context,
    String message, {
    SnackType type = SnackType.info,
    IconData? icon,
    Duration duration = const Duration(seconds: 3),
  }) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Colors & icons based on type
    Color bgColor;
    Color fgColor = Colors.white;
    IconData defaultIcon;

    switch (type) {
      case SnackType.success:
        bgColor = Colors.green.shade600;
        defaultIcon = Icons.check_circle;
        break;
      case SnackType.error:
        bgColor = colors.error;
        fgColor = colors.onError;
        defaultIcon = Icons.error;
        break;
      case SnackType.info:
        bgColor = colors.primaryContainer;
        fgColor = colors.onPrimaryContainer;
        defaultIcon = Icons.info;
        break;
    }

    final overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) {
      // fallback to regular snackbar if overlay not available
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          elevation: 0, // 🚫 disable default shadow
          backgroundColor: Colors.transparent, // 🚫 disable default bg
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: AppTheme.spaceXXL * AppTheme.spaceScale(context)), // float above action bar
          content: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: AppTheme.spaceMD * AppTheme.spaceScale(context), 
                    vertical: AppTheme.spaceMD * AppTheme.spaceScale(context),
                  ),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                  boxShadow: [
                    BoxShadow(
                      color: colors.shadow.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    )
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon ?? defaultIcon, 
                      color: fgColor, 
                      size: AppTheme.iconSM * AppTheme.iconScale(context),
                    ),
                    const SizedBox(width: AppTheme.spaceSM),
                    Flexible(
                      child: Text(
                        message,
                        style: textTheme.bodySmall?.copyWith(color: fgColor),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          duration: duration,
        ),
      );
      return;
    }

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _OverlaySnack(
        message: message,
        bgColor: bgColor,
        fgColor: fgColor,
        icon: icon ?? defaultIcon,
        onRequestClose: () {
          entry.remove();
        },
        duration: duration,
      ),
    );

    overlay.insert(entry);
  }
}

/// Internal widget displayed inside overlay entry.
/// Handles its own animation and removal after [duration].
class _OverlaySnack extends StatefulWidget {
  final String message;
  final Color bgColor;
  final Color fgColor;
  final IconData icon;
  final Duration duration;
  final VoidCallback onRequestClose;

  const _OverlaySnack({
    required this.message,
    required this.bgColor,
    required this.fgColor,
    required this.icon,
    required this.duration,
    required this.onRequestClose,
    Key? key,
  }) : super(key: key);

  @override
  State<_OverlaySnack> createState() => _OverlaySnackState();
}

class _OverlaySnackState extends State<_OverlaySnack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _offsetAnim;
  late final Animation<double> _fadeAnim;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _offsetAnim = Tween<Offset>(
      begin: const Offset(0, -0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);

    _ctrl.forward();

    _dismissTimer = Timer(widget.duration, _hide);
  }

  void _hide() {
    _dismissTimer?.cancel();
    _ctrl.reverse().then((_) {
      if (mounted) {
        widget.onRequestClose();
      } else {
        widget.onRequestClose();
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom + AppTheme.spaceXXL;
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Positioned(
      bottom: bottomPadding,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: false,
        child: Center(
          child: SlideTransition(
            position: _offsetAnim,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    margin: EdgeInsets.symmetric(
                      horizontal: AppTheme.spaceMD * AppTheme.spaceScale(context)
                    ),
                    padding: EdgeInsets.symmetric(
                        horizontal: AppTheme.spaceMD * AppTheme.spaceScale(context), 
                        vertical: AppTheme.spaceMD * AppTheme.spaceScale(context),
                      ),
                    decoration: BoxDecoration(
                      color: widget.bgColor,
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusLG * AppTheme.radiusScale(context)
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors.shadow.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.icon, 
                          color: widget.fgColor, 
                          size: AppTheme.iconSM * AppTheme.iconScale(context),
                        ),
                        SizedBox(width: AppTheme.spaceSM * AppTheme.spaceScale(context)),
                        Flexible(
                          child: Text(
                            widget.message,
                            style: textTheme.bodySmall?.copyWith(color: widget.fgColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
