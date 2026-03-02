import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/utils/helper.dart';
import 'package:nadekodon/utils/api_service.dart';
import 'package:nadekodon/utils/logger.dart';
import 'package:nadekodon/utils/settings.dart';
import 'package:nadekodon/ui/widgets/components/dir_choose.dart';

import 'package:nadekodon/src/bindings/bindings.dart';

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

  late PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    if (widget.output != null && widget.output!.items.isNotEmpty) {
      widget.nameController.text = widget.output!.items.first.name;
    }
  }

  @override
  void didUpdateWidget(YtdlpView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.output != oldWidget.output &&
        widget.output != null &&
        widget.output!.items.isNotEmpty) {
      widget.nameController.text = widget.output!.items.first.name;
      _currentIndex = 0;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.output == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return _buildView(widget.output!);
  }

  Widget _buildItemView(YtdlItem item) {
    final colors = Theme.of(context).colorScheme;
    final isDesktop = AppTheme.isDesktop(context);

    Widget buildThumbnail() => Image.network(
      APIService.wrapImageUrl(item.thumbnail!),
      fit: BoxFit.contain,
      headers: kIsWeb
          ? {'X-API-Key': SettingsManager.serverApiKey.value}
          : null,
      errorBuilder: (context, error, stackTrace) {
        log("Error fetching image $error", isError: true);
        return Container(
          color: colors.surfaceContainerHighest,
          child: Center(
            child: Icon(Icons.broken_image, color: colors.onSurfaceVariant),
          ),
        );
      },
    );

    Widget buildSelectors() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        if (item.videos.isNotEmpty) ...[
          _buildFormatSelector("Video", item.videos, selectedVideo, (format) {
            setState(() => selectedVideo = format);
            widget.onVideoChanged(format);
          }),
          const SizedBox(height: AppTheme.spaceMD),
        ],
        if (item.audios.isNotEmpty)
          _buildFormatSelector("Audio", item.audios, selectedAudio, (format) {
            setState(() => selectedAudio = format);
            widget.onAudioChanged(format);
          }),
      ],
    );

    if (isDesktop) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (item.thumbnail != null) ...[
              Expanded(flex: 2, child: SizedBox(child: buildThumbnail())),
              SizedBox(width: AppTheme.spaceMD * AppTheme.spaceScale(context)),
            ],
            Expanded(
              flex: 3,
              child: Align(
                alignment: Alignment.centerLeft,
                child: buildSelectors(),
              ),
            ),
          ],
        ),
      );
    } else {
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (item.thumbnail != null) ...[
              SizedBox(
                height: 5 * AppTheme.spaceXXL * AppTheme.spaceScale(context),
                child: buildThumbnail(),
              ),
              SizedBox(height: AppTheme.spaceMD * AppTheme.spaceScale(context)),
            ],
            buildSelectors(),
          ],
        ),
      );
    }
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

    final items = ytdlOutput.items;
    if (items.isEmpty) {
      return Center(
        child: Text(
          "No items found",
          style: textTheme.bodyMedium?.copyWith(color: colors.error),
        ),
      );
    }

    Widget pageViewBuilder = PageView.builder(
      controller: _pageController,
      itemCount: items.length,
      onPageChanged: (index) {
        setState(() {
          _currentIndex = index;
          selectedVideo = null;
          selectedAudio = null;
          widget.onVideoChanged(null);
          widget.onAudioChanged(null);
          widget.nameController.text = items[index].name;
        });
      },
      itemBuilder: (context, index) {
        return _buildItemView(items[index]);
      },
    );

    Widget pageNavigator = const SizedBox.shrink();
    if (items.length > 1) {
      pageNavigator = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              if (_currentIndex > 0) {
                _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              }
            },
          ),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(items.length, (index) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4.0),
                    width: _currentIndex == index ? 12.0 : 8.0,
                    height: 8.0,
                    decoration: BoxDecoration(
                      color: _currentIndex == index
                          ? colors.primary
                          : colors.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4.0),
                    ),
                  );
                }),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              if (_currentIndex < items.length - 1) {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              }
            },
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 240,
          width: 400 * AppTheme.widthScale(context),
          child: pageViewBuilder,
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
        if (items.length > 1) ...[
          SizedBox(height: AppTheme.spaceSM * AppTheme.spaceScale(context)),
          pageNavigator,
        ],
      ],
    );
  }

  Widget _buildFormatSelector(
    String title,
    List<YtdlFormat> formats,
    YtdlFormat? selectedFormat,
    void Function(YtdlFormat?) onChanged,
  ) {
    if (selectedFormat != null && !formats.contains(selectedFormat)) {
      selectedFormat = null;
    }

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
