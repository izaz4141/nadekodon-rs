// lib/ui/pages/download_page.dart
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../widgets/dialog/add_download.dart';
import 'package:nadekodon/utils/helper.dart';

import 'package:rinf/rinf.dart';
import 'package:nadekodon/src/bindings/bindings.dart';

enum DownloadStatus { queued, running, paused, completed, cancelled, failed }

DownloadStatus parseDownloadStatus(String state) {
  final s = state.toLowerCase();
  if (s.contains('error')) return DownloadStatus.failed;
  switch (s) {
    case 'queued':
      return DownloadStatus.queued;
    case 'running':
      return DownloadStatus.running;
    case 'paused':
      return DownloadStatus.paused;
    case 'completed':
      return DownloadStatus.completed;
    case 'cancelled':
      return DownloadStatus.cancelled;
    case 'error':
      return DownloadStatus.failed;
    default:
      return DownloadStatus.failed;
  }
}

class DownloadItem {
  final String id;
  final String name;
  final int downloaded;
  final int? total;
  final DownloadStatus status;
  final double speed;

  const DownloadItem({
    required this.id,
    required this.name,
    required this.downloaded,
    required this.total,
    required this.status,
    required this.speed,
  });

  double get progress =>
      (total != null && total! > 0) ? downloaded / total! : 0.0;
}

class DownloadPage extends StatelessWidget {
  const DownloadPage({super.key});

  static const activeStatuses = {
    DownloadStatus.queued,
    DownloadStatus.running,
    DownloadStatus.paused,
  };

  static const completedStatuses = {
    DownloadStatus.completed,
    DownloadStatus.cancelled,
    DownloadStatus.failed,
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text("Downloads", style: textTheme.titleLarge),
          bottom: TabBar(
            labelStyle: textTheme.bodyMedium?.copyWith(
              color: colors.primary,
            ),
            unselectedLabelStyle: textTheme.bodyMedium,
            splashBorderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLG)),
            tabs: [
              Tab(text: "Active"),
              Tab(text: "Completed"),
            ],
          ),
        ),
        body: StreamBuilder(
          stream: DownloadList.rustSignalStream,
          builder: (context, snapshot) {
            final signalPack = snapshot.data;
            if (signalPack == null) {
              return TabBarView(
                children: [
                  const Center(child: CircularProgressIndicator()),
                  const Center(child: CircularProgressIndicator()),
                ]
              );
            }
            final downloadListOutput = signalPack.message;
            final downloads = downloadListOutput.list;

            final downloadItems = downloads.map<DownloadItem>((d) {
              final status = parseDownloadStatus(d.state);
              return DownloadItem(
                id: d.id,
                name: d.name,
                downloaded: d.downloaded.toInt(),
                total: d.totalSize?.toInt(),
                status: status,
                speed:d.speed,
              );
            }).toList();

            final activeDownloads = downloadItems
                .where((d) => activeStatuses.contains(d.status))
                .toList();
            final completedDownloads = downloadItems
                .where((d) => completedStatuses.contains(d.status))
                .toList();

            return TabBarView(
              children: [
                _buildDownloadList(
                    context, activeDownloads, "No active downloads"),
                _buildDownloadList(
                    context, completedDownloads, "No completed downloads"),
              ],
            );
          },
        ),
        floatingActionButton: Padding(
          padding: const EdgeInsets.all(AppTheme.spaceMD),
          child: FloatingActionButton(
            onPressed: () => showAddDownloadDialog(context),
            tooltip: 'Add download',
            child: const Icon(Icons.add),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }

  Widget _buildDownloadList(
      BuildContext context, List<DownloadItem> items, String emptyMessage) {
    if (items.isEmpty) {
      return Center(
        child: Text(emptyMessage,
            style: Theme.of(context).textTheme.bodyMedium),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spaceSM),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return DownloadTile(
          item: items[index],
          onPauseResume: () {
            if (items[index].status == DownloadStatus.running ||
                items[index].status == DownloadStatus.queued) {
                PauseDownload(id: items[index].id).sendSignalToRust();
            } else {
                ResumeDownload(id: items[index].id).sendSignalToRust();
            }
          },
          onCancel: () {
            if ( activeStatuses.contains(items[index].status)) {
              CancelDownload(id: items[index].id).sendSignalToRust();
            }
          }
        );
      },
    );
  }
}

class DownloadTile extends StatelessWidget {
  final DownloadItem item;
  final VoidCallback onPauseResume;
  final VoidCallback onCancel;

  const DownloadTile({
    super.key,
    required this.item,
    required this.onPauseResume,
    required this.onCancel,
  });

  Color _progressColor(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    switch (item.status) {
      case DownloadStatus.queued:
        return Colors.blueGrey;
      case DownloadStatus.running:
        return colors.primary;
      case DownloadStatus.paused:
        return colors.secondary;
      case DownloadStatus.completed:
        return Colors.green;
      case DownloadStatus.cancelled:
        return Colors.blueGrey;
      case DownloadStatus.failed:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.symmetric(
        vertical: AppTheme.spaceXS,
        horizontal: AppTheme.spaceMD,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spaceSM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name + Status row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(item.name,
                      style: textTheme.bodyMedium),
                ),
                Text(
                  item.status.name.toUpperCase(),
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _progressColor(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceSM),
            LinearProgressIndicator(
              value: item.progress,
              backgroundColor: colors.surfaceVariant,
              color: _progressColor(context),
              minHeight: AppTheme.spaceSM * AppTheme.spaceScale(context),
              borderRadius: BorderRadius.circular(AppTheme.radiusSM * AppTheme.radiusScale(context)),
            ),
            const SizedBox(height: AppTheme.spaceSM),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      item.total != null
                          ? "${formatBytes(item.downloaded)} / ${formatBytes(item.total!)}"
                          : formatBytes(item.downloaded),
                      style: textTheme.bodySmall,
                    ),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.center,
                    child: Text(
                      "${formatBytes(item.speed.toInt())}/s",
                      style: textTheme.bodySmall,
                    ),
                  ),
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.stop),
                          iconSize: AppTheme.iconMD * AppTheme.iconScale(context),
                          onPressed: onCancel,
                        ),
                        IconButton(
                          icon: Icon(
                            (item.status == DownloadStatus.running ||
                                    item.status == DownloadStatus.queued)
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                          iconSize: AppTheme.iconMD * AppTheme.iconScale(context),
                          onPressed: onPauseResume,
                        ),
                      ]
                    )
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
