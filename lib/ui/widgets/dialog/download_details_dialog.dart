import 'package:flutter/material.dart';
import 'package:nadekodon/src/bindings/bindings.dart';
import 'package:nadekodon/ui/pages/download_page.dart';
import 'package:nadekodon/theme/app_theme.dart';
import 'package:nadekodon/utils/helper.dart';

class DownloadDetailsDialog extends StatefulWidget {
  final DownloadItem item;

  const DownloadDetailsDialog({super.key, required this.item});

  @override
  State<DownloadDetailsDialog> createState() => _DownloadDetailsDialogState();
}

class _DownloadDetailsDialogState extends State<DownloadDetailsDialog> {
  @override
  void initState() {
    super.initState();
    GetDownloadDetails(id: widget.item.id).sendSignalToRust();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      title: Text('Download Details', style: textTheme.titleMedium),
      content: StreamBuilder(
        stream: DownloadDetails.rustSignalStream,
        builder: (context, snapshot) {
          final signalPack = snapshot.data;
          if (signalPack == null) {
            return const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final details = signalPack.message;
          if (details.id != widget.item.id) {
            // Keep showing loading if the signal is for another download
            // Ideally we should filter the stream, but for now this simple check works
            // if we assume only one details dialog is open at a time.
            // A better approach would be to filter the stream in the stream property.
            return const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          return SingleChildScrollView(
            child: SelectionArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow('Name', details.name, textTheme),
                  const SizedBox(height: AppTheme.spaceSM),
                  _buildDetailRow('URL', details.url, textTheme),
                  const SizedBox(height: AppTheme.spaceSM),
                  _buildDetailRow('Destination', details.dest, textTheme),
                  const SizedBox(height: AppTheme.spaceSM),
                  _buildDetailRow(
                    'Size',
                    details.totalSize != null
                        ? formatBytes(details.totalSize!.toInt())
                        : 'Unknown',
                    textTheme,
                  ),
                  const SizedBox(height: AppTheme.spaceSM),
                  _buildDetailRow(
                    'Downloaded',
                    formatBytes(details.downloaded.toInt()),
                    textTheme,
                  ),
                  const SizedBox(height: AppTheme.spaceSM),
                  _buildDetailRow(
                    'Speed',
                    '${formatBytes(details.speed.toInt())}/s',
                    textTheme,
                  ),
                  const SizedBox(height: AppTheme.spaceSM),
                  _buildDetailRow('Status', details.state, textTheme),
                ],
              ),
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close', style: textTheme.bodyMedium),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(value, style: textTheme.bodyMedium),
      ],
    );
  }
}
