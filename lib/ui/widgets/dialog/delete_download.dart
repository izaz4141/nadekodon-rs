import 'package:flutter/material.dart';
import 'package:nadekodon/ui/pages/download_page.dart';
import 'package:nadekodon/utils/logger.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/helper.dart';
import '../app_snackbar.dart';
import '../../../src/bindings/bindings.dart';

/// Shows a dialog to confirm deletion of a download
Future<void> showDeleteDownloadDialog(
  BuildContext context,
  DownloadItem item,
) async {
  bool deleteFromList = true;
  bool deleteFile = false;

  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final textTheme = Theme.of(context).textTheme;

      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text('Delete Download', style: textTheme.titleMedium),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  title: Text('Remove from list', style: textTheme.bodyMedium),
                  value: deleteFromList,
                  onChanged: (value) {
                    setState(() {
                      deleteFromList = value ?? true;
                    });
                  },
                ),
                CheckboxListTile(
                  title: Text(
                    'Delete downloaded file',
                    style: textTheme.bodyMedium,
                  ),
                  value: deleteFile,
                  onChanged: (value) {
                    setState(() {
                      deleteFile = value ?? false;
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel', style: textTheme.bodyMedium),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Delete', style: textTheme.bodyMedium),
              ),
            ],
          );
        },
      );
    },
  );

  if (result != true || !context.mounted) return;

  // Delete file if requested
  if (deleteFile) {
    try {
      await deleteDownloadFile(item.dest);
      if (context.mounted) {
        AppSnackBar.show(
          context,
          "File deleted successfully",
          type: SnackType.success,
        );
      }
    } catch (e) {
      if (context.mounted) {
        AppSnackBar.show(
          context,
          "Failed to delete file",
          type: SnackType.error,
        );
        log('Failed to delete file: $e');
      }
    }
  }

  // Remove from list if requested
  if (deleteFromList) {
    DeleteDownload(id: item.id).sendSignalToRust();
    if (context.mounted) {
      AppSnackBar.show(
        context,
        "Download removed from list",
        type: SnackType.success,
      );
    }
  }
}
