import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nadekodon/theme/app_theme.dart';
import 'package:nadekodon/utils/settings.dart';
import 'package:nadekodon/ui/widgets/app_snackbar.dart';
import 'package:nadekodon/ui/widgets/components/section_header.dart';
import 'package:nadekodon/ui/widgets/components/spin_box.dart';

class SettingsWS extends StatelessWidget {
  const SettingsWS({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'WebSocket Settings',
          icon: Icons.network_wifi,
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            iconSize: AppTheme.iconMD * AppTheme.iconScale(context),
            tooltip: "Restart Server",
            onPressed: () {
              SettingsManager.restartServer();
              AppSnackBar.show(context, "Server restarted");
            },
          ),
        ),
        SpinBox(
          title: "Server Port",
          subtitle: "Port to listen on",
          valueListenable: SettingsManager.serverPort,
          min: 1024,
          max: 65535,
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
