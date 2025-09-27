// lib/ui/widgets/settings/actions_bar.dart
import 'package:flutter/material.dart';
import '../../../utils/settings.dart';
import '../app_snackbar.dart';

class SettingsActionsBar extends StatelessWidget {
  final ColorScheme colors;

  const SettingsActionsBar({super.key, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(25),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                SettingsManager.retreatToTray.value = true;
                SettingsManager.downloadFolder.value = '';
                SettingsManager.serverPort.value = 8080;
                SettingsManager.speedLimit.value = 2.0;

                AppSnackBar.show(
                  context,
                  "Settings reset to defaults",
                  icon: Icons.restart_alt,
                );
              },
              icon: const Icon(Icons.restart_alt, size: 20),
              label: const Text('Reset'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                AppSnackBar.show(
                  context,
                  "Settings saved",
                  type: SnackType.success,
                );
              },
              icon: const Icon(Icons.save_rounded, size: 20),
              label: const Text('Save'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                elevation: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
