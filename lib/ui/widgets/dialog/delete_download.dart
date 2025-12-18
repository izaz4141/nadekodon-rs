import 'package:flutter/material.dart';

import '../../../utils/helper.dart';
import '../app_snackbar.dart';
import '../../../src/bindings/bindings.dart';
import '../../../theme/app_theme.dart';

/// Shows a dialog to confirm deletion of one or more downloads
Future<void> showDeleteDownloadsDialog(
  BuildContext context,
  List<DownloadItem> items, {
  VoidCallback? onDeleted,
}) async {
  if (items.isEmpty) return;

  bool deleteFromList = true;
  bool deleteFile = false;
  final isMultiple = items.length > 1;

  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final textTheme = Theme.of(context).textTheme;

      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(
              isMultiple ? 'Delete Selected' : 'Delete Download',
              style: textTheme.titleMedium,
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isMultiple)
                  Text(
                    'Are you sure you want to delete ${items.length} items?',
                    style: textTheme.bodyMedium,
                  )
                else
                  Text(
                    'Are you sure you want to delete this download?',
                    style: textTheme.bodyMedium,
                  ),
                const SizedBox(height: AppTheme.spaceMD),
                CheckboxListTile(
                  title: Text('Remove from list', style: textTheme.bodyMedium),
                  value: deleteFromList,
                  onChanged: (value) {
                    setState(() {
                      deleteFromList = value ?? true;
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  title: Text(
                    isMultiple
                        ? 'Delete downloaded files'
                        : 'Delete downloaded file',
                    style: textTheme.bodyMedium,
                  ),
                  value: deleteFile,
                  onChanged: (value) {
                    setState(() {
                      deleteFile = value ?? false;
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
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

  int successCount = 0;
  for (final item in items) {
    if (deleteFromList) {
      DeleteDownload(id: item.id, deleteFile: deleteFile).sendSignalToRust();
    }
    successCount++;
  }

  if (context.mounted) {
    final message = isMultiple
        ? "Deleted $successCount items"
        : "Download removed from list";
    AppSnackBar.show(context, message, type: SnackType.success);
    onDeleted?.call();
  }
}
