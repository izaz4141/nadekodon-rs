// lib/ui/widgets/settings/download_folder_tile.dart
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../../theme/app_theme.dart';
import '../../../utils/settings.dart';

class DownloadFolderTile extends StatelessWidget {
  const DownloadFolderTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: SettingsManager.downloadFolder,
      builder: (context, value, _) {
        final colors = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        return ListTile(
          title: Text(
            "Download Folder", 
            style: textTheme.bodyMedium,
          ),
          subtitle: Text(
            value.isEmpty ? "No Folder Selected" : value,
            style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          trailing: 
            IconButton(
              padding: EdgeInsets.symmetric(
                horizontal: AppTheme.spaceXL * AppTheme.spaceScale(context),
                vertical: AppTheme.spaceSM * AppTheme.spaceScale(context),
              ),
              icon: const Icon(Icons.folder_open),
              iconSize: AppTheme.iconMD * AppTheme.spaceScale(context),
              onPressed: () async {
                String? selectedDirectory = await FilePicker.platform
                    .getDirectoryPath();
                if (selectedDirectory != null) {
                  SettingsManager.downloadFolder.value = selectedDirectory;
                }
              },
            ),
        );
      },
    );
  }
}
