import 'package:flutter/material.dart';

enum DownloadStatus { running, paused, done, failed }

class DownloadItem {
  final String id;
  final String name;
  final int downloaded; // bytes downloaded so far
  final int? total;     // null if unknown
  final DownloadStatus status;

  const DownloadItem({
    required this.id,
    required this.name,
    required this.downloaded,
    required this.total,
    required this.status,
  });

  double get progress =>
      (total != null && total! > 0) ? downloaded / total! : 0.0;
}

class DownloadPage extends StatelessWidget {
  const DownloadPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    // Fake list of downloads (replace later with your Rust signal data)
    final downloads = [
      DownloadItem(
        id: "1",
        name: "Ubuntu ISO",
        downloaded: 400 * 1024 * 1024,
        total: 1024 * 1024 * 1024,
        status: DownloadStatus.running,
      ),
      DownloadItem(
        id: "2",
        name: "Music Album.zip",
        downloaded: 250 * 1024 * 1024,
        total: 250 * 1024 * 1024,
        status: DownloadStatus.done,
      ),
      DownloadItem(
        id: "3",
        name: "Large Video.mp4",
        downloaded: 150 * 1024 * 1024,
        total: 800 * 1024 * 1024,
        status: DownloadStatus.paused,
      ),
      DownloadItem(
        id: "4",
        name: "Book.pdf",
        downloaded: 10 * 1024 * 1024,
        total: 50 * 1024 * 1024,
        status: DownloadStatus.failed,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Downloads"),
      ),
      body: ListView.builder(
        itemCount: downloads.length,
        itemBuilder: (context, index) {
          return DownloadTile(
            item: downloads[index],
            onPauseResume: () {
              // TODO: Send pause/resume signal to Rust
              debugPrint("Toggled ${downloads[index].id}");
            },
          );
        },
      ),
    );
  }
}

class DownloadTile extends StatelessWidget {
  final DownloadItem item;
  final VoidCallback onPauseResume;

  const DownloadTile({
    super.key,
    required this.item,
    required this.onPauseResume,
  });

  Color _progressColor(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    switch (item.status) {
      case DownloadStatus.running:
        return colors.primary;
      case DownloadStatus.paused:
        return colors.secondary;
      case DownloadStatus.done:
        return Colors.green;
      case DownloadStatus.failed:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Name + Status row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(item.name,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Text(
                  item.status.name.toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _progressColor(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Progress bar
            LinearProgressIndicator(
              value: item.progress,
              backgroundColor: colors.surfaceVariant,
              color: _progressColor(context),
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 8),
            // Downloaded / Total + Pause/Resume button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  item.total != null
                      ? "${_formatBytes(item.downloaded)} / ${_formatBytes(item.total!)}"
                      : "${_formatBytes(item.downloaded)}",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                IconButton(
                  icon: Icon(
                    item.status == DownloadStatus.running
                        ? Icons.pause
                        : Icons.play_arrow,
                  ),
                  onPressed: onPauseResume,
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    const suffixes = ["B", "KB", "MB", "GB"];
    double size = bytes.toDouble();
    int i = 0;
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return "${size.toStringAsFixed(1)} ${suffixes[i]}";
  }
}
