// lib/ui/widgets/settings/actions_bar.dart
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
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
      bottom: AppTheme.spaceXXL,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(AppTheme.radiusMD * AppTheme.radiusScale(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(25),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        padding: EdgeInsets.symmetric(
          vertical: AppTheme.spaceMD * AppTheme.spaceScale(context), 
          horizontal: AppTheme.spaceLG * AppTheme.spaceScale(context)),
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
              icon: Icon(Icons.restart_alt, 
                size: AppTheme.iconMD * AppTheme.iconScale(context)),
              label: Text('Reset',
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.primary)
              ),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: AppTheme.spaceLG * AppTheme.spaceScale(context) ,
                  vertical: AppTheme.spaceMD * AppTheme.spaceScale(context),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD * AppTheme.radiusScale(context)),
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
              icon: Icon(Icons.save_rounded, 
                size: AppTheme.iconMD * AppTheme.iconScale(context)),
              label: Text('Save', 
                style: textTheme.bodyMedium?.copyWith(
                    color: colors.onPrimary)
              ),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  horizontal: AppTheme.spaceLG * AppTheme.spaceScale(context) ,
                  vertical: AppTheme.spaceMD * AppTheme.spaceScale(context),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD * AppTheme.radiusScale(context)),
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
