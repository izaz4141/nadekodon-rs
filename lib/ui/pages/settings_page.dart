// lib/ui/pages/settings_page.dart
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../widgets/settings/download_folder_tile.dart';
import '../widgets/settings/server_port_spinbox.dart';
import '../widgets/settings/speed_limit_spinbox.dart';
import '../widgets/settings/download_thread_spinbox.dart';
import '../widgets/settings/max_download_spinbox.dart';
import '../widgets/settings/tray_switch_tile.dart';
import '../widgets/settings/actions_bar.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings', style: textTheme.titleLarge),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: AppTheme.spaceSM,
            ),
            child: ListView(
              children: [
                DownloadFolderTile(),
                PortSpinBox(),
                SpeedLimitSpinBox(),
                DownloadThreadBox(),
                MaxDownloadBox(),
                Divider(),
                TraySwitchTile(),
              ],
            ),
          ),
          SettingsActionsBar(colors: colors),
        ],
      ),
    );
  }
}
