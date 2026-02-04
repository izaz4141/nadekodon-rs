import 'package:flutter/material.dart';

import 'package:nadekodon/utils/settings.dart';
import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/ui/widgets/dialog/account_manager_dialog.dart';

class AccountSwitcher extends StatelessWidget {
  final VoidCallback? onAccountSwitch;

  const AccountSwitcher({super.key, this.onAccountSwitch});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ValueListenableBuilder<String>(
      valueListenable: SettingsManager.serverHost,
      builder: (context, host, _) {
        return InkWell(
          onTap: () {
            if (onAccountSwitch != null) onAccountSwitch!();
            _showAccountManager(context);
          },
          borderRadius: BorderRadius.circular(AppTheme.radiusMD),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: AppTheme.radiusMD * AppTheme.radiusScale(context),
                  backgroundColor: colors.primaryContainer,
                  child: Icon(
                    Icons.person,
                    size: AppTheme.iconMD * AppTheme.iconScale(context),
                    color: colors.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: AppTheme.spaceMD),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        SettingsManager.username.value,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        host == '127.0.0.1' || host == 'localhost'
                            ? 'Local Session'
                            : host,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.swap_horiz,
                  size: AppTheme.iconMD * AppTheme.iconScale(context),
                  color: colors.primary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAccountManager(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const AccountManagerDialog(),
    );
  }
}
