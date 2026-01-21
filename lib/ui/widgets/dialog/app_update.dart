import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/utils/system_service.dart';

class AppUpdateDialog extends StatelessWidget {
  final VersionInfo versionInfo;

  const AppUpdateDialog({super.key, required this.versionInfo});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    final releaseNotesContent = versionInfo.releaseNotes;
    final bool hasReleaseNotes = releaseNotesContent.isNotEmpty;

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'Update Available',
              style: textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(false),
            iconSize: AppTheme.iconMD * AppTheme.iconScale(context),
          ),
        ],
      ),
      content: SizedBox(
        width: AppTheme.dialogWidth(context),
        height: AppTheme.dialogMaxHeight(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Version ${versionInfo.version}',
              style: textTheme.titleSmall?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: AppTheme.spaceSM),
            Text(
              'Release Notes',
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: AppTheme.spaceXS),
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSM),
                  ),
                  padding: const EdgeInsets.all(AppTheme.spaceSM),
                  child: hasReleaseNotes
                      ? GptMarkdown(
                          releaseNotesContent,
                          style: textTheme.bodyMedium?.copyWith(
                            color: colors.onSurface,
                          ),
                        )
                      : Text(
                          'No release notes available.',
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: textTheme.bodyMedium),
        ),
        Tooltip(
          message:
              'The app will download and install the update, then restart automatically.',
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Update', style: textTheme.bodyMedium),
          ),
        ),
      ],
    );
  }
}
