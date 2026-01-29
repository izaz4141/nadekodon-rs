import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import 'package:nadekodon/utils/platform_service.dart';
import 'package:nadekodon/utils/api_service.dart';
import 'package:nadekodon/ui/widgets/app_snackbar.dart';
import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/utils/helper.dart';
import 'package:nadekodon/ui/widgets/dialog/delete_download.dart';
import 'package:nadekodon/ui/widgets/dialog/download_details_dialog.dart';
import 'package:nadekodon/ui/widgets/dialog/update_url_dialog.dart';

/// Shows a context menu for a download item
Future<void> showDownloadContextMenu(
  BuildContext context,
  Offset position,
  DownloadItem item, {
  VoidCallback? onDelete,
}) async {
  final RenderBox overlay =
      Overlay.of(context).context.findRenderObject() as RenderBox;
  final textTheme = Theme.of(context).textTheme;

  final result = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      position & const Size(40, 40),
      Offset.zero & overlay.size,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTheme.radiusSM),
      side: BorderSide(color: Theme.of(context).dividerColor, width: 1),
    ),
    items: [
      if (kIsWeb &&
          (item.status == DownloadStatus.completed ||
              item.status == DownloadStatus.seeding))
        PopupMenuItem<String>(
          value: 'download',
          child: Row(
            children: [
              Icon(
                Icons.download_outlined,
                size: AppTheme.iconSM * AppTheme.iconScale(context),
              ),
              SizedBox(width: AppTheme.spaceSM),
              Text('Download', style: textTheme.bodySmall),
            ],
          ),
        ),
      PopupMenuItem<String>(
        value: 'open_file',
        child: Row(
          children: [
            Icon(
              Icons.open_in_new,
              size: AppTheme.iconSM * AppTheme.iconScale(context),
            ),
            SizedBox(width: AppTheme.spaceXS),
            Text('Open file', style: textTheme.bodySmall),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'show_in_folder',
        child: Row(
          children: [
            Icon(
              Icons.folder_open,
              size: AppTheme.iconSM * AppTheme.iconScale(context),
            ),
            SizedBox(width: AppTheme.spaceSM),
            Text('Show in folder', style: textTheme.bodySmall),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'update_url',
        child: Row(
          children: [
            Icon(
              Icons.edit_outlined,
              size: AppTheme.iconSM * AppTheme.iconScale(context),
            ),
            SizedBox(width: AppTheme.spaceSM),
            Text('Update URL', style: textTheme.bodySmall),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'delete',
        child: Row(
          children: [
            Icon(
              Icons.delete_outline,
              size: AppTheme.iconSM * AppTheme.iconScale(context),
            ),
            SizedBox(width: AppTheme.spaceSM),
            Text('Delete', style: textTheme.bodySmall),
          ],
        ),
      ),
      if (PlatformService.isDesktop && !PlatformService.isLinux)
        PopupMenuItem<String>(
          value: 'share',
          child: Row(
            children: [
              Icon(
                Icons.share_outlined,
                size: AppTheme.iconSM * AppTheme.iconScale(context),
              ),
              SizedBox(width: AppTheme.spaceSM),
              Text('Share', style: textTheme.bodySmall),
            ],
          ),
        ),
      PopupMenuItem<String>(
        value: 'info',
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: AppTheme.iconSM * AppTheme.iconScale(context),
            ),
            SizedBox(width: AppTheme.spaceSM),
            Text('Info', style: textTheme.bodySmall),
          ],
        ),
      ),
    ],
  );

  if (!context.mounted) return;

  switch (result) {
    case 'open_file':
      final openResult = await openFile(item.dest);
      if (openResult != ResultType.done && context.mounted) {
        final message = openResult == ResultType.fileNotFound
            ? 'File does not exist'
            : 'Error opening file';
        AppSnackBar.show(context, message, type: SnackType.error);
      }
      break;
    case 'show_in_folder':
      final success = await showInFolder(item.dest);
      if (!success && context.mounted) {
        AppSnackBar.show(
          context,
          'Error showing folder',
          type: SnackType.error,
        );
      }
      break;
    case 'share':
      if (await fileExist(item.dest)) {
        final xFile = XFile(item.dest);
        await SharePlus.instance.share(ShareParams(files: [xFile]));
      } else {
        if (context.mounted) {
          AppSnackBar.show(context, 'File not found', type: SnackType.error);
        }
      }
      break;
    case 'info':
      showDialog(
        context: context,
        builder: (context) => DownloadDetailsDialog(item: item),
      );
      break;
    case 'update_url':
      await showDialog<String>(
        context: context,
        builder: (context) =>
            UpdateUrlDialog(id: item.id, currentUrl: '', referer: item.referer),
      );
      break;
    case 'delete':
      if (onDelete != null) {
        onDelete();
      } else {
        await showDeleteDownloadsDialog(context, [item]);
      }
      break;
    case 'download':
      final url = APIService.getDownloadUrl(item.id);
      await launchUrl(Uri.parse(url));
      break;
  }
}
