import 'package:flutter/material.dart';
import 'package:nadekodon/src/bindings/bindings.dart';
import 'package:nadekodon/theme/app_theme.dart';
import 'package:nadekodon/utils/helper.dart';

class YtdlDownloadView extends StatefulWidget {
  final YtdlQueryOutput ytdlOutput;
  final String selectedDir;
  final void Function(String name, YtdlFormat? video, YtdlFormat? audio) onDownload;

  const YtdlDownloadView({
    super.key,
    required this.ytdlOutput,
    required this.selectedDir,
    required this.onDownload,
  });

  @override
  State<YtdlDownloadView> createState() => _YtdlDownloadViewState();
}

class _YtdlDownloadViewState extends State<YtdlDownloadView> {
  final _nameController = TextEditingController();
  YtdlFormat? _selectedVideo;
  YtdlFormat? _selectedAudio;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.ytdlOutput.name;
    if (widget.ytdlOutput.videos.isNotEmpty) {
      _selectedVideo = widget.ytdlOutput.videos.first;
    }
    if (widget.ytdlOutput.audios.isNotEmpty) {
      _selectedAudio = widget.ytdlOutput.audios.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.ytdlOutput.thumbnail != null)
              Expanded(
                flex: 2,
                child: Image.network(
                  widget.ytdlOutput.thumbnail!,
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
                  if (widget.ytdlOutput.videos.isNotEmpty)
                    _buildFormatSelector("Video", widget.ytdlOutput.videos, _selectedVideo, (format) {
                      setState(() => _selectedVideo = format);
                    }),
                  const SizedBox(height: AppTheme.spaceMD),
                  if (widget.ytdlOutput.audios.isNotEmpty)
                    _buildFormatSelector("Audio", widget.ytdlOutput.audios, _selectedAudio, (format) {
                      setState(() => _selectedAudio = format);
                    }),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spaceMD),
        TextField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: "Filename",
            labelStyle: textTheme.bodyMedium,
            floatingLabelStyle: textTheme.bodySmall?.copyWith(
              color: colors.primary,
            ),
            border: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppTheme.radiusMD)),
            ),
          ),
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: AppTheme.spaceLG),
        ElevatedButton(
          onPressed: () {
            widget.onDownload(_nameController.text, _selectedVideo, _selectedAudio);
          },
          child: Text("Download", style: textTheme.labelLarge),
        )
      ],
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
