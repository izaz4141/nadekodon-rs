import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/utils/settings.dart';
import 'package:nadekodon/ui/widgets/app_snackbar.dart';
import 'package:nadekodon/ui/widgets/components/section_header.dart';
import 'package:nadekodon/ui/widgets/components/spin_box.dart';
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
        SpinBox(
          title: "Server Port",
          subtitle: "Port to listen on",
          valueListenable: SettingsManager.serverPort,
          min: 1024,
          max: 65535,
        ),
        _buildTextField(
          context: context,
          textTheme: textTheme,
          colors: colors,
          title: "Username",
          subtitle: "qBittorrent API username",
          valueListenable: SettingsManager.username,
        ),
        _buildTextField(
          context: context,
          textTheme: textTheme,
          colors: colors,
          title: "Password",
          subtitle: "qBittorrent API password",
          valueListenable: SettingsManager.password,
          isObscured: true,
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

  Widget _buildTextField({
    required BuildContext context,
    required TextTheme textTheme,
    required ColorScheme colors,
    required String title,
    required String subtitle,
    required ValueListenable<String> valueListenable,
    bool isObscured = false,
  }) {
    final obscureNotifier = ValueNotifier<bool>(isObscured);

    return ValueListenableBuilder<String>(
      valueListenable: valueListenable,
      builder: (context, value, _) {
        final controller = TextEditingController.fromValue(
          TextEditingValue(
            text: value,
            selection: TextSelection.collapsed(offset: value.length),
          ),
        );
        return ListTile(
          title: Text(title, style: textTheme.bodyMedium),
          subtitle: Text(subtitle, style: textTheme.bodySmall),
          trailing: SizedBox(
            width: 200 * AppTheme.spaceScale(context),
            child: ValueListenableBuilder<bool>(
              valueListenable: obscureNotifier,
              builder: (context, obscureText, _) {
                return TextField(
                  controller: controller,
                  obscureText: obscureText,
                  style: textTheme.bodyMedium,
                  decoration: InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal:
                          AppTheme.spaceSM * AppTheme.spaceScale(context),
                      vertical: AppTheme.spaceSM * AppTheme.spaceScale(context),
                    ),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(
                        Radius.circular(AppTheme.radiusSM),
                      ),
                    ),
                    suffixIcon: isObscured
                        ? IconButton(
                            icon: Icon(
                              obscureText
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            iconSize:
                                AppTheme.iconSM * AppTheme.iconScale(context),
                            onPressed: () {
                              obscureNotifier.value = !obscureNotifier.value;
                            },
                          )
                        : null,
                  ),
                  onChanged: (newValue) {
                    if (valueListenable is ValueNotifier<String>) {
                      valueListenable.value = newValue;
                    }
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}
