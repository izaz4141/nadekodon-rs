// lib/ui/widgets/app_snackbar.dart
import 'package:flutter/material.dart';

enum SnackType { success, error, info }

class AppSnackBar {
  static void show(
    BuildContext context,
    String message, {
    SnackType type = SnackType.info,
    IconData? icon, // 👈 custom icon
    Duration duration = const Duration(seconds: 3),
  }) {
    final colors = Theme.of(context).colorScheme;

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
        bgColor = Colors.red.shade600;
        defaultIcon = Icons.error;
        break;
      case SnackType.info:
        bgColor = colors.primaryContainer;
        fgColor = colors.onPrimaryContainer;
        defaultIcon = Icons.info;
        break;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 0, // 🚫 disable default shadow
        backgroundColor: Colors.transparent, // 🚫 disable default bg
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 80), // float above action bar
        content: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(50),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon ?? defaultIcon, color: fgColor, size: 20),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      message,
                      style: TextStyle(
                        color: fgColor,
                        fontWeight: FontWeight.w500,
                      ),
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
  }
}
