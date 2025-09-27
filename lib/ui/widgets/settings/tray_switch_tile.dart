// lib/ui/widgets/settings/speed_limit_spinbox.dart
import 'package:flutter/material.dart';
import '../../../utils/settings.dart';

class TraySwitchTile extends StatelessWidget {
  const TraySwitchTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: SettingsManager.retreatToTray,
      builder: (context, value, _) {
        return SwitchListTile(
          title: const Text("Close to system tray"),
          subtitle: const Text(
            "Minimize to system tray instead of exiting the application",
            style: TextStyle(color: Colors.grey),
          ),
          value: value,
          onChanged: (newValue) {
            SettingsManager.retreatToTray.value = newValue;
          },
        );
      },
    );
  }
}
