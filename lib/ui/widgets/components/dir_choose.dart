import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../../theme/app_theme.dart';

class DirChoose extends StatelessWidget {
  final ValueNotifier<String> selectedDir;
  
  const DirChoose({
    super.key,
    required this.selectedDir,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    
    return Row(
      children: [
        Expanded(
          child: Text(
            selectedDir.value ?? "No directory selected",
            style: textTheme.bodySmall?.copyWith(
              color: (selectedDir.value.isEmpty)
                  ? colors.onSurfaceVariant
                  : colors.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppTheme.spaceSM),
        ElevatedButton.icon(
          icon: Icon(
            Icons.folder_open,
            size: AppTheme.iconSM * AppTheme.iconScale(context),
          ),
          label: Text(
            "Choose",
            style: TextStyle(
              fontSize: AppTheme.textMD * AppTheme.textScale(context),
            ),
          ),
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.symmetric(
              horizontal: AppTheme.spaceSM * AppTheme.spaceScale(context),
              vertical: AppTheme.spaceSM * AppTheme.spaceScale(context),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMD),
            ),
          ),
          onPressed: () async {
            final dir = await FilePicker.platform.getDirectoryPath();
            if (dir != null) {
              selectedDir.value = dir;
            }
          },
        ),
      ],
    );
  }
}