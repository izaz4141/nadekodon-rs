// lib/ui/widgets/settings/speed_limit_spinbox.dart
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../utils/settings.dart';

class TraySwitchTile extends StatelessWidget {
  const TraySwitchTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsManager.retreatToTray,
      builder: (context, value, _) {
        final colors = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        return ListTile(
          title: Text("Close to system tray", style: textTheme.bodyMedium),
          subtitle: Text(
            "Minimize to system tray instead of exiting the application",
            style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          trailing: Transform.scale(
            scale: AppTheme.iconScale(context),
            alignment: Alignment.centerRight,
            child: Switch(
              value: value,
              onChanged: (newValue) {
                SettingsManager.retreatToTray.value = newValue;
              },
            ),
          ),
        );
      },
    );
  }
}
