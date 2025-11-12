import 'package:flutter/material.dart';

import 'package:nadekodon/theme/app_theme.dart';
import 'package:nadekodon/utils/helper.dart';
import 'package:nadekodon/ui/widgets/components/dir_choose.dart';

import 'package:rinf/rinf.dart';
import 'package:nadekodon/src/bindings/bindings.dart';

class YtdlpView extends StatefulWidget {
  final TextEditingController nameController;
  final ValueNotifier<String> selectedDir;
  final void Function() onDownload;
  final ValueChanged<YtdlFormat?> onVideoChanged;
  final ValueChanged<YtdlFormat?> onAudioChanged;

  const YtdlpView({
    super.key,
    required this.nameController,
    required this.selectedDir,
    required this.onDownload,
    required this.onVideoChanged,
    required this.onAudioChanged,
  });

  @override
  State<YtdlpView> createState() => _YtdlpView();
}

class _YtdlpView extends State<YtdlpView> {
  YtdlFormat? selectedVideo;
  YtdlFormat? selectedAudio;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: YtdlQueryOutput.rustSignalStream,
      builder: (context, snapshot) {
        final signalPack = snapshot.data;
        if (signalPack == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final ytdlOutput = signalPack.message;
        widget.nameController.text = ytdlOutput.name;

        final colors = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (ytdlOutput.thumbnail != null)
                  Expanded(
                    flex: 2,
                    child: Image.network(
                      ytdlOutput.thumbnail!,
                      // height: 5 * AppTheme.spaceXXL * AppTheme.spaceScale(context),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        // height: 5 * AppTheme.spaceXXL * AppTheme.spaceScale(context),
                        color: colors.surfaceVariant,
                        child: Center(
                          child: Icon(Icons.broken_image, color: colors.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: AppTheme.spaceMD),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (ytdlOutput.videos.isNotEmpty)
                        _buildFormatSelector("Video", ytdlOutput.videos, selectedVideo, (format) {
                          setState(() => selectedVideo = format);
                          widget.onVideoChanged(format);
                        }),
                      const SizedBox(height: AppTheme.spaceMD),
                      if (ytdlOutput.audios.isNotEmpty)
                        _buildFormatSelector("Audio", ytdlOutput.audios, selectedAudio, (format) {
                          setState(() => selectedAudio = format);
                          widget.onAudioChanged(format);
                        }),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spaceMD),
            TextField(
              controller: widget.nameController,
              onSubmitted: (_) => widget.onDownload(),
              decoration: InputDecoration(
                labelText: "Filename",
                labelStyle: textTheme.bodyMedium,
                floatingLabelStyle: textTheme.bodySmall?.copyWith(
                  color: colors.primary,
                ),
                hintText: "No format needed",
                hintStyle: textTheme.bodyMedium,
                border: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(AppTheme.radiusMD)),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spaceSM,
                  vertical: AppTheme.spaceSM,
                ),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: widget.nameController,
                  builder: (context, value, child) {
                    if (value.text.isEmpty) {
                      return const SizedBox.shrink(); // Hide button if empty
                    }
                    return IconButton(
                      icon: const Icon(Icons.clear),
                      tooltip: "Clear",
                      onPressed: () => widget.nameController.clear(),
                    );
                  },
                ),
              ),
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: AppTheme.spaceSM),
            DirChoose(selectedDir: widget.selectedDir),
          ],
        );
      },
    );
  }

  Widget _buildFormatSelector(
    String title,
    List<YtdlFormat> formats,
    YtdlFormat? selectedFormat,
    void Function(YtdlFormat?) onChanged,
  ) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: textTheme.titleMedium),
        DropdownButton<YtdlFormat>(
          value: selectedFormat,
          isExpanded: true,
          items: formats.map((format) {
            return DropdownMenuItem<YtdlFormat>(
              value: format,
              child: Text(
                "${format.note} - ${format.ext} - ${format.vcodec != null && format.vcodec != 'none' ? format.vcodec : (format.acodec != null && format.acodec != 'none' ? format.acodec : '')} - ${format.filesize != null ? formatBytes(format.filesize!.toInt()) : 'N/A'}",
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium,
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}
