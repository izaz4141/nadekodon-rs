import 'package:flutter/material.dart';

import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/utils/helper.dart';
import 'package:nadekodon/ui/widgets/components/dir_choose.dart';
import 'package:nadekodon/utils/system_service.dart';

import 'package:nadekodon/src/bindings/bindings.dart';

class QueryResultView extends StatefulWidget {
  final TextEditingController urlController;
  final TextEditingController nameController;
  final ValueNotifier<String> selectedDir;
  final ValueNotifier<String?> selectedCategory;
  final ValueNotifier<bool> queryFinished;
  final ValueNotifier<bool> isQueryingYtdl;
  final void Function() onDownload;
  final void Function() onQueryYtdl;
  final UrlQueryOutput? output;

  const QueryResultView({
    super.key,
    required this.urlController,
    required this.nameController,
    required this.selectedDir,
    required this.selectedCategory,
    required this.queryFinished,
    required this.isQueryingYtdl,
    required this.onDownload,
    required this.onQueryYtdl,
    required this.output,
  });

  @override
  State<QueryResultView> createState() => _QueryResultViewState();
}

class _QueryResultViewState extends State<QueryResultView> {
  @override
  void initState() {
    super.initState();
    final system = SystemService();
    if (system.ytdlpVersion.value == null ||
        system.ffmpegVersion.value == null) {
      system.fetchVersions();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.output == null) {
      return _buildLoading(context);
    }
    return _buildView(context, widget.output!);
  }

  Widget _buildLoading(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        CircularProgressIndicator(
          color: Colors.green.shade600,
          strokeWidth: 2,
          constraints: BoxConstraints(
            minWidth: AppTheme.iconSM * AppTheme.iconScale(context),
            maxWidth: AppTheme.iconSM * AppTheme.iconScale(context),
            minHeight: AppTheme.iconSM * AppTheme.iconScale(context),
            maxHeight: AppTheme.iconSM * AppTheme.iconScale(context),
          ),
        ),
        const SizedBox(width: AppTheme.spaceSM),
        Text(
          "Querying info...",
          style: textTheme.bodySmall?.copyWith(color: Colors.green.shade600),
        ),
      ],
    );
  }

  Widget _buildView(BuildContext context, UrlQueryOutput urlQuery) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final showDetails = !urlQuery.error || urlQuery.isWebpage;

    if (!widget.queryFinished.value && showDetails) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.queryFinished.value = true;
        widget.nameController.text = urlQuery.isWebpage
            ? "index.html"
            : urlQuery.name;
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (urlQuery.error)
          Padding(
            padding: const EdgeInsets.only(top: AppTheme.spaceSM),
            child: Text(
              "✖ URL can't be reached",
              style: textTheme.bodySmall?.copyWith(
                color: Colors.red.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (showDetails) ...[
          const SizedBox(height: AppTheme.spaceSM),
          TextField(
            controller: widget.nameController,
            onSubmitted: (_) => widget.onDownload(),
            decoration: InputDecoration(
              labelText: "Filename",
              labelStyle: textTheme.bodyMedium,
              floatingLabelStyle: textTheme.bodyMedium?.copyWith(
                color: colors.primary,
              ),
              hintText: "download.bin",
              hintStyle: textTheme.bodyMedium,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(
                  Radius.circular(AppTheme.radiusMD),
                ),
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
          DirChoose(
            selectedDir: widget.selectedDir,
            selectedCategory: widget.selectedCategory,
          ),
          const SizedBox(height: AppTheme.spaceSM),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (urlQuery.isWebpage)
                AnimatedBuilder(
                  animation: Listenable.merge([
                    SystemService().ytdlpVersion,
                    SystemService().ffmpegVersion,
                  ]),
                  builder: (context, _) {
                    final ytdlp = SystemService().ytdlpVersion.value;
                    final ffmpeg = SystemService().ffmpegVersion.value;

                    return Row(
                      children: [
                        Text(
                          "RETURNED WEBPAGE",
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.error,
                          ),
                        ),
                        if (ytdlp != null && ffmpeg != null) ...[
                          const SizedBox(width: AppTheme.spaceMD),
                          ElevatedButton(
                            onPressed: widget.onQueryYtdl,
                            child: Text("YTDL", style: textTheme.bodySmall),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              if (!urlQuery.error)
                Text(
                  "Filesize: ${urlQuery.totalSize != null ? formatBytes(urlQuery.totalSize!.toInt()) : '?'}",
                  style: textTheme.bodySmall,
                ),
            ],
          ),
        ],
      ],
    );
  }
}
