import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/ui/widgets/components/section_header.dart';
import 'package:nadekodon/utils/settings.dart';
import 'package:nadekodon/ui/widgets/dialog/permission_dialog.dart';
import 'package:nadekodon/utils/platform_service.dart';

class SettingsMisc extends StatelessWidget {
  const SettingsMisc({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Misc',
          leading: Icon(
            Icons.miscellaneous_services_rounded,
            color: colors.onPrimaryContainer,
            size: AppTheme.iconMD * AppTheme.iconScale(context),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: SettingsManager.checkNightly,
          builder: (context, checkNightly, _) {
            return ListTile(
              title: Text(
                "Check for Nightly Updates",
                style: textTheme.bodyMedium,
              ),
              subtitle: Text(
                "Include pre-release versions in update checks",
                style: textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              trailing: Switch(
                value: checkNightly,
                onChanged: (value) {
                  SettingsManager.checkNightly.value = value;
                },
              ),
            );
          },
        ),
        if (!kIsWeb && PlatformService.isAndroid) ...[
          ListTile(
            title: Text("Check Permissions", style: textTheme.bodyMedium),
            subtitle: Text(
              "Manage app permissions",
              style: textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            onTap: () => showDialog(
              context: context,
              builder: (context) => const PermissionDialog(),
            ),
            trailing: Icon(
              Icons.chevron_right,
              size: AppTheme.iconMD * AppTheme.iconScale(context),
            ),
          ),
        ],
      ],
    );
  }
}
