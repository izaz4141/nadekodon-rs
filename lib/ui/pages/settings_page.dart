// lib/ui/pages/settings_page.dart
import 'dart:io';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'package:nadekodon/ui/widgets/view/settings_dm.dart';
import 'package:nadekodon/ui/widgets/view/settings_ui.dart';
import 'package:nadekodon/ui/widgets/view/settings_ws.dart';
import 'package:nadekodon/ui/widgets/components/settings_actions_bar.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDesktop = AppTheme.isDesktop(context);

    return Scaffold(
      appBar: isDesktop
          ? AppBar(title: Text('Settings', style: textTheme.titleLarge))
          : null,
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceSM),
            child: ListView(
              children: [
                SettingsDM(),
                Divider(),
                SettingsUI(),
                if (!Platform.isAndroid) ...[Divider(), SettingsWS()],
                SizedBox(height: 120 * AppTheme.heightScale(context)),
              ],
            ),
          ),
          SettingsActionsBar(colors: colors),
        ],
      ),
    );
  }
}
