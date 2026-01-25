import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/utils/settings.dart';
import 'package:nadekodon/ui/widgets/app_snackbar.dart';
import 'package:nadekodon/ui/widgets/components/section_header.dart';
import 'package:nadekodon/ui/widgets/components/spin_box.dart';
import 'package:nadekodon/ui/widgets/components/list_text_field.dart';
import 'package:nadekodon/utils/api_service.dart';

class SettingsSec extends StatelessWidget {
  const SettingsSec({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Security Settings',
          icon: Icons.network_wifi,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: APIService.isOnline,
                builder: (context, isOnline, _) {
                  return IconButton(
                    icon: Icon(
                      Icons.refresh,
                      color: isOnline
                          ? colors.onPrimaryContainer
                          : colors.error,
                    ),
                    iconSize: AppTheme.iconMD * AppTheme.iconScale(context),
                    tooltip: isOnline ? "Server Online" : "Server Offline",
                    onPressed: () {
                      SettingsManager.restartServer();
                      APIService.restartPolling();
                      AppSnackBar.show(context, "Server restarted");
                    },
                  );
                },
              ),
            ],
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: SettingsManager.requireLogin,
          builder: (context, value, _) {
            return ListTile(
              title: Text("Require Login", style: textTheme.bodyMedium),
              subtitle: Text(
                "Show login screen on startup",
                style: textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              trailing: Transform.scale(
                scale: AppTheme.iconScale(context),
                alignment: Alignment.centerRight,
                child: Switch(
                  value: value,
                  onChanged: (newValue) {
                    SettingsManager.requireLogin.value = newValue;
                  },
                ),
              ),
            );
          },
        ),
        SpinBox(
          title: "Server Port",
          subtitle: "Port to listen on",
          valueListenable: SettingsManager.serverPort,
          min: 1024,
          max: 65535,
        ),
        AutofillGroup(
          child: Column(
            children: [
              ListTextField(
                title: "Username",
                subtitle: "qBittorrent API username",
                valueListenable: SettingsManager.username,
                autofillHints: AutofillHints.newUsername,
              ),
              ListTextField(
                title: "Password",
                subtitle: "qBittorrent API password",
                valueListenable: SettingsManager.password,
                isObscured: true,
                autofillHints: AutofillHints.newPassword,
                onConfirm: (newValue) {
                  SettingsManager.password.value = newValue;
                  TextInput.finishAutofillContext();
                },
              ),
            ],
          ),
        ),
        _buildApiKeyDisplay(context, textTheme, colors),
      ],
    );
  }

  Widget _buildApiKeyDisplay(
    BuildContext context,
    TextTheme textTheme,
    ColorScheme colors,
  ) {
    return ListTile(
      title: Text("API Key", style: textTheme.bodyMedium),
      subtitle: ValueListenableBuilder<String>(
        valueListenable: SettingsManager.serverApiKey,
        builder: (context, key, _) {
          return SelectableText(
            key,
            style: textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          );
        },
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.copy),
            iconSize: AppTheme.iconMD * AppTheme.iconScale(context),
            tooltip: "Copy API Key",
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: SettingsManager.serverApiKey.value),
              );
              AppSnackBar.show(context, "API Key copied to clipboard");
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            iconSize: AppTheme.iconMD * AppTheme.iconScale(context),
            tooltip: "Regenerate API Key",
            onPressed: () {
              SettingsManager.regenerateApiKey();
              AppSnackBar.show(context, "API Key regenerated");
            },
          ),
        ],
      ),
    );
  }
}
