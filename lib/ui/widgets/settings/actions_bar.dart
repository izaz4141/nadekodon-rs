// lib/ui/widgets/settings/actions_bar.dart
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../utils/defaults.dart';
import '../../../utils/settings.dart';
import '../app_snackbar.dart';

class SettingsActionsBar extends StatelessWidget {
  final ColorScheme colors;

  const SettingsActionsBar({super.key, required this.colors});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Positioned(
      left: AppTheme.spaceLG,
      right: AppTheme.spaceLG,
      bottom: AppTheme.spaceXL,
      child: Container(
        margin: EdgeInsets.symmetric(
            vertical: AppTheme.spaceMD * AppTheme.spaceScale(context),
            horizontal: AppTheme.spaceLG * AppTheme.spaceScale(context)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton.icon(
              onPressed: () {
                SettingsManager.retreatToTray.value = DefaultSettings.retreatToTray;
                SettingsManager.downloadFolder.value = DefaultSettings.downloadFolder;
                SettingsManager.serverPort.value = DefaultSettings.serverPort;
                SettingsManager.speedLimit.value = DefaultSettings.speedLimit;
                SettingsManager.downloadThreads.value = DefaultSettings.downloadThreads;
                SettingsManager.concurrencyLimit.value = DefaultSettings.concurrencyLimit;

                AppSnackBar.show(
                  context,
                  "Settings reset to defaults",
                  icon: Icons.restart_alt,
                );
              },
              icon: Icon(Icons.restart_alt,
                  size: AppTheme.iconMD * AppTheme.iconScale(context)),
              label: Text('Reset',
                  style: textTheme.bodyMedium?.copyWith(color: colors.primary)),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: AppTheme.spaceLG * AppTheme.spaceScale(context),
                  vertical: AppTheme.spaceMD * AppTheme.spaceScale(context),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                      AppTheme.radiusMD * AppTheme.radiusScale(context)),
                ),
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              ),
            ),
            // ElevatedButton.icon(
            //   onPressed: () {
            //     AppSnackBar.show(
            //       context,
            //       "Settings saved",
            //       type: SnackType.success,
            //     );
            //   },
            //   icon: Icon(Icons.save_rounded,
            //       size: AppTheme.iconMD * AppTheme.iconScale(context)),
            //   label: Text('Save',
            //       style: textTheme.bodyMedium
            //           ?.copyWith(color: colors.onPrimary)),
            //   style: ElevatedButton.styleFrom(
            //     padding: EdgeInsets.symmetric(
            //       horizontal: AppTheme.spaceLG * AppTheme.spaceScale(context),
            //       vertical: AppTheme.spaceMD * AppTheme.spaceScale(context),
            //     ),
            //     shape: RoundedRectangleBorder(
            //       borderRadius: BorderRadius.circular(
            //           AppTheme.radiusMD * AppTheme.radiusScale(context)),
            //     ),
            //     backgroundColor: colors.primary,
            //     foregroundColor: colors.onPrimary,
            //     elevation: 3,
            //   ),
            // ),
          ],
        ),
      ),
    );
  }
}
