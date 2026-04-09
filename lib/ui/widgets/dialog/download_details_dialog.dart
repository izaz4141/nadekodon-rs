import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nadekodon/src/bindings/bindings.dart';
import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/utils/helper.dart';
import 'package:nadekodon/ui/widgets/app_snackbar.dart';
import 'package:nadekodon/utils/download_service.dart';

class DownloadDetailsDialog extends StatefulWidget {
  final DownloadItem item;

  const DownloadDetailsDialog({super.key, required this.item});

  @override
  State<DownloadDetailsDialog> createState() => _DownloadDetailsDialogState();
}

class _DownloadDetailsDialogState extends State<DownloadDetailsDialog> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sendSignal();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _sendSignal();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _sendSignal() {
    DownloadService().fetchDetails(widget.item.id);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.download_rounded, color: colorScheme.primary),
          const SizedBox(width: AppTheme.spaceSM),
          Text('Download Details', style: textTheme.titleMedium),
        ],
      ),
      content: SizedBox(
        width: AppTheme.dialogWidth(context),
        child: StreamBuilder<DownloadDetails>(
          stream: DownloadService().getDetailsStream(widget.item.id),
          builder: (context, snapshot) {
            final details = snapshot.data;
            if (details == null) {
              return const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (details.id != widget.item.id) {
              return const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spaceLG,
                ),
                child: SelectionArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoSection(details, textTheme, colorScheme),
                      const SizedBox(height: AppTheme.spaceMD),
                      const Divider(),
                      const SizedBox(height: AppTheme.spaceMD),
                      Text('Parts Progress', style: textTheme.titleSmall),
                      const SizedBox(height: AppTheme.spaceSM),
                      _buildPartsList(details.partInfo, colorScheme),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close', style: textTheme.bodyMedium),
        ),
      ],
    );
  }

  Widget _buildInfoSection(
    DownloadDetails details,
    TextTheme textTheme,
    ColorScheme colorScheme,
  ) {
    final hasTorrentDetails = details.uploaded != null || details.peers != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDetailRow('Name', details.name, textTheme, scrollable: true),
        const SizedBox(height: AppTheme.spaceSM),
        _buildDetailRow(
          'URL',
          details.url,
          textTheme,
          trailing: IconButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: details.url));
              if (mounted) {
                AppSnackBar.show(context, 'URL copied to clipboard');
              }
            },
            icon: const Icon(Icons.copy),
            tooltip: 'Copy URL',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              iconSize: AppTheme.iconMD * AppTheme.iconScale(context),
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spaceSM),
        _buildDetailRow('Destination', details.dest, textTheme, scrollable: true),
        const SizedBox(height: AppTheme.spaceSM),
        Row(
          children: [
            Expanded(
              child: _buildDetailRow(
                'Downloaded',
                formatBytes(details.downloaded.toInt()),
                textTheme,
              ),
            ),
            Expanded(
              child: _buildDetailRow(
                'Size',
                details.totalSize != null
                    ? formatBytes(details.totalSize!.toInt())
                    : 'Unknown',
                textTheme,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spaceSM),
        Row(
          children: [
            Expanded(
              child: _buildDetailRow(
                'Speed',
                '${formatBytes(details.speed.toInt())}/s',
                textTheme,
              ),
            ),
            Expanded(
              child: _buildDetailRow('Status', details.state, textTheme),
            ),
          ],
        ),
        if (hasTorrentDetails) ...[
          const SizedBox(height: AppTheme.spaceSM),
          Row(
            children: [
              if (details.uploaded != null)
                Expanded(
                  child: _buildDetailRow(
                    'Uploaded',
                    formatBytes(details.uploaded!.toInt()),
                    textTheme,
                  ),
                ),
              if (details.uploadSpeed != null)
                Expanded(
                  child: _buildDetailRow(
                    'Upload Speed',
                    '${formatBytes(details.uploadSpeed!.toInt())}/s',
                    textTheme,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppTheme.spaceSM),
          Row(
            children: [
              if (details.peers != null)
                Expanded(
                  child: _buildDetailRow(
                    'Peers',
                    '${details.peers}',
                    textTheme,
                  ),
                ),
              if (details.ratio != null)
                Expanded(
                  child: _buildDetailRow(
                    'Ratio',
                    details.ratio!.toStringAsFixed(2),
                    textTheme,
                  ),
                ),
            ],
          ),
          if (details.eta != null) ...[
            const SizedBox(height: AppTheme.spaceSM),
            _buildDetailRow('ETA', details.eta!, textTheme),
          ],
        ],
      ],
    );
  }

  Widget _buildDetailRow(
    String label,
    String value,
    TextTheme textTheme, {
    Widget? trailing,
    bool scrollable = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
        const SizedBox(height: AppTheme.spaceXS),
        Row(
          children: [
            Expanded(
              child: scrollable
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(
                        value,
                        style: textTheme.bodyMedium,
                      ),
                    )
                  : Text(
                      value,
                      style: textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppTheme.spaceXS),
              trailing,
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildPartsList(List<PartInfo> parts, ColorScheme colorScheme) {
    if (parts.isEmpty) {
      return const Text('No part information available.');
    }

    return Column(
      children: parts.asMap().entries.map((entry) {
        // final index = entry.key;
        final part = entry.value;
        final start = part.start.toBigInt();
        final end = part.end.toBigInt();
        final current = part.current.toBigInt();
        final total = end - start;
        final progress = total > BigInt.zero
            ? current.toDouble() / total.toDouble()
            : 0.0;

        return Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.spaceXS),
          child: Row(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final double availableWidth = constraints.maxWidth;
                    const double blockSize = AppTheme.spaceSM;
                    const double spacing = AppTheme.spaceXS;

                    // Calculate how many blocks fit
                    // width = n * size + (n - 1) * spacing
                    // width = n * (size + spacing) - spacing
                    // width + spacing = n * (size + spacing)
                    final int blockCount =
                        ((availableWidth + spacing) / (blockSize + spacing))
                            .floor();

                    // Ensure at least 1 block
                    final int count = blockCount > 0 ? blockCount : 1;

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 0; i < count; i++) ...[
                          if (i > 0) const SizedBox(width: spacing),
                          Container(
                            width: blockSize,
                            height: blockSize,
                            decoration: BoxDecoration(
                              color: progress >= (i + 1) / count
                                  ? colorScheme.primary
                                  : colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
