import 'package:flutter/material.dart';

import '../../../utils/helper.dart';
import '../app_snackbar.dart';
import '../../../src/bindings/bindings.dart';
import '../../../theme/app_theme.dart';

/// Shows a dialog to confirm deletion of multiple downloads
Future<void> showDeleteMultipleDownloadsDialog(
  BuildContext context,
  List<DownloadItem> items, {
  required VoidCallback onDeleted,
}) async {
  bool deleteFromList = true;
  bool deleteFile = false;

  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final textTheme = Theme.of(context).textTheme;
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Delete Selected'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Are you sure you want to delete ${items.length} items?',
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
                ),
                CheckboxListTile(
                  title: Text(
                    'Delete downloaded files',
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
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
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
    AppSnackBar.show(
      context,
      "Deleted $successCount items",
      type: SnackType.success,
    );
    onDeleted();
  }
}
