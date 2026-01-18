import 'package:flutter/material.dart';

import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/utils/helper.dart';
import 'package:nadekodon/ui/widgets/components/dir_choose.dart';

import 'package:nadekodon/src/bindings/bindings.dart';
import 'package:nadekodon/utils/api_service.dart';

class YtdlpView extends StatefulWidget {
  final TextEditingController nameController;
  final ValueNotifier<String> selectedDir;
  final void Function() onDownload;
  final ValueChanged<YtdlFormat?> onVideoChanged;
  final ValueChanged<YtdlFormat?> onAudioChanged;
  final YtdlQueryOutput? output;

  const YtdlpView({
    super.key,
    required this.nameController,
    required this.selectedDir,
    required this.onDownload,
    required this.onVideoChanged,
    required this.onAudioChanged,
    required this.output,
  });

  @override
  State<YtdlpView> createState() => _YtdlpView();
}

class _YtdlpView extends State<YtdlpView> {
  YtdlFormat? selectedVideo;
  YtdlFormat? selectedAudio;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.output == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return _buildView(widget.output!);
  }

  Widget _buildView(YtdlQueryOutput ytdlOutput) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (ytdlOutput.error != null) {
      return Center(
        child: Text(
          ytdlOutput.error!,
          style: textTheme.bodyMedium?.copyWith(color: colors.error),
        ),
      );
    }

    widget.nameController.text = ytdlOutput.name;
    final isDesktop = AppTheme.isDesktop(context);

    Widget buildThumbnail() => Image.network(
      APIService.wrapImageUrl(ytdlOutput.thumbnail!),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        color: colors.surfaceContainerHighest,
        child: Center(
          child: Icon(Icons.broken_image, color: colors.onSurfaceVariant),
        ),
      ),
    );

    Widget buildSelectors() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ytdlOutput.videos.isNotEmpty)
          _buildFormatSelector("Video", ytdlOutput.videos, selectedVideo, (
            format,
          ) {
            setState(() => selectedVideo = format);
            widget.onVideoChanged(format);
          }),
        const SizedBox(height: AppTheme.spaceMD),
        if (ytdlOutput.audios.isNotEmpty)
          _buildFormatSelector("Audio", ytdlOutput.audios, selectedAudio, (
            format,
          ) {
            setState(() => selectedAudio = format);
            widget.onAudioChanged(format);
          }),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isDesktop)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (ytdlOutput.thumbnail != null) ...[
                  Expanded(flex: 2, child: SizedBox(child: buildThumbnail())),
                  SizedBox(
                    width: AppTheme.spaceMD * AppTheme.spaceScale(context),
                  ),
                ],
                Expanded(flex: 3, child: buildSelectors()),
              ],
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (ytdlOutput.thumbnail != null) ...[
                SizedBox(
                  height: 5 * AppTheme.spaceXXL * AppTheme.spaceScale(context),
                  child: buildThumbnail(),
                ),
                SizedBox(
                  height: AppTheme.spaceMD * AppTheme.spaceScale(context),
                ),
              ],
              buildSelectors(),
            ],
          ),
        SizedBox(height: AppTheme.spaceMD * AppTheme.spaceScale(context)),
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
              borderRadius: BorderRadius.all(
                Radius.circular(AppTheme.radiusMD),
              ),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: AppTheme.spaceSM * AppTheme.spaceScale(context),
              vertical: AppTheme.spaceSM * AppTheme.spaceScale(context),
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
        SizedBox(height: AppTheme.spaceSM * AppTheme.spaceScale(context)),
        DirChoose(selectedDir: widget.selectedDir),
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
    final isDesktop = AppTheme.isDesktop(context);

    Widget buildDropdown() => DropdownButton<YtdlFormat>(
      value: selectedFormat,
      isExpanded: true,
      isDense: true,
      itemHeight: null,
      items: [
        DropdownMenuItem<YtdlFormat>(
          value: null,
          child: Text("None", style: textTheme.bodyMedium),
        ),
        ...formats.map((format) {
          return DropdownMenuItem<YtdlFormat>(
            value: format,
            child: Text(
              "${format.note} - ${format.ext} - ${format.vcodec != null && format.vcodec != 'none' ? format.vcodec : (format.acodec != null && format.acodec != 'none' ? format.acodec : '')} - ${format.filesize != null ? formatBytes(format.filesize!.toInt()) : 'N/A'}",
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium,
            ),
          );
        }),
      ],
      onChanged: onChanged,
    );

    if (isDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.titleMedium),
          buildDropdown(),
        ],
      );
    } else {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 1,
            child: Text("$title:", style: textTheme.titleSmall),
          ),
          Expanded(flex: 5, child: buildDropdown()),
        ],
      );
    }
  }
}
