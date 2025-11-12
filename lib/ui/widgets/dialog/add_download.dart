import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';

import '../../../theme/app_theme.dart';
import '../../../utils/settings.dart';
import '../app_snackbar.dart';
import 'package:nadekodon/utils/helper.dart';
import 'ytdl_download_view.dart';

import 'package:rinf/rinf.dart';
import 'package:nadekodon/src/bindings/bindings.dart';

Future<void> showAddDownloadDialog(BuildContext context) async {
  await showDialog(
    context: context,
    builder: (context) {
      return _AddDownloadDialog();
    },
  );
}

class _AddDownloadDialog extends StatefulWidget {
  const _AddDownloadDialog({Key? key}) : super(key: key);

  @override
  State<_AddDownloadDialog> createState() => _AddDownloadDialogState();
}

class _AddDownloadDialogState extends State<_AddDownloadDialog> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  String? _selectedDir = SettingsManager.downloadFolder.value;

  bool _showQueryInfo = false;
  bool _queryFinished = false;
  bool _isQueryingYtdl = false;
  YtdlQueryOutput? _ytdlOutput;

  @override
  void initState() {
    super.initState();
    _getClipboardContent();
    YtdlQueryOutput.rustSignalStream.listen((signal) {
      if (mounted) {
        setState(() {
          _ytdlOutput = signal.message;
          _isQueryingYtdl = false;
        });
      }
    });
  }

  Future<void> _getClipboardContent() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final clipboardText = clipboardData?.text;
    if (clipboardText != null && isUrl(clipboardText)) {
      setState(() {
        _urlController.text = clipboardText;
      });
    }
  }

  void _handleSubmit() {
    final url = _urlController.text.trim();
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      AppSnackBar.show(context, "Please enter a filename.", type: SnackType.error);
      return;
    }
    Navigator.pop(context);
    DoDownload(url: url, dest: "${_selectedDir!}/$name", isYtdl: false).sendSignalToRust();
    AppSnackBar.show(context, "Added download");
  }

  void _handleYtdlDownload(String name, YtdlFormat? video, YtdlFormat? audio) {
    var vFormat = null;
    var aFormat = null;
    if (video != null) {
      vFormat = video;
    }
    if (audio != null) {
      aFormat = audio;
    }
    Navigator.pop(context);
    DoDownload(
      url: null,
      dest: "${_selectedDir!}/$name",
      videoFormat: vFormat,
      audioFormat: aFormat,
      isYtdl: true,
    ).sendSignalToRust();
    AppSnackBar.show(context, "Added ytdl download");
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_ytdlOutput != null) {
      return AlertDialog(
        title: Text("YTDL Download"),
        content: YtdlDownloadView(
          ytdlOutput: _ytdlOutput!,
          selectedDir: _selectedDir!,
          onDownload: _handleYtdlDownload,
        ),
      );
    }

    if (_isQueryingYtdl) {
      return const AlertDialog(
        title: Text("Querying YTDL..."),
        content: Center(child: CircularProgressIndicator()),
      );
    }

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
      ),
      title: Text("New Download"),
      content: _buildInitialView(),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Cancel", style: textTheme.bodyMedium),
        ),
        ElevatedButton(
          onPressed: _queryFinished ? _handleSubmit : _queryUrl,
          child: Text(
            _queryFinished ? "Download" : "Query",
            style: textTheme.bodyMedium?.copyWith(color: colors.primary),
          ),
        ),
      ],
    );
  }

  void _queryUrl() {
    final url = _urlController.text.trim();
    if (url.isEmpty || !isUrl(url)) {
      AppSnackBar.show(context, "Please enter a valid URL", type: SnackType.error);
      return;
    }
    if (_selectedDir == null || _selectedDir!.isEmpty) {
      AppSnackBar.show(context, "Please select a destination folder", type: SnackType.error);
      return;
    }
    QueryUrl(url: url).sendSignalToRust();
    setState(() {
      _showQueryInfo = true;
    });
  }

  Widget _buildInitialView() {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: 400 * AppTheme.widthScale(context),
        maxWidth: AppTheme.dialogWidth(context),
        maxHeight: AppTheme.dialogMaxHeight(context),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_queryFinished) ...[
            TextField(
              controller: _urlController,
              onSubmitted: (_) => _handleSubmit(),
              decoration: InputDecoration(
                labelText: "Download URL",
                labelStyle: textTheme.bodyMedium,
                floatingLabelStyle: textTheme.bodySmall?.copyWith(
                  color: colors.primary,
                ),
                hintText: "https://example.com/file.zip",
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
              ),
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: AppTheme.spaceLG),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  _selectedDir ?? "No directory selected",
                  style: textTheme.bodySmall?.copyWith(
                    color: (_selectedDir == null || _selectedDir!.isEmpty)
                        ? colors.onSurfaceVariant
                        : colors.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppTheme.spaceSM),
              ElevatedButton.icon(
                icon: Icon(
                  Icons.folder_open,
                  size: AppTheme.iconSM * AppTheme.iconScale(context),
                ),
                label: Text(
                  "Choose",
                  style: TextStyle(
                    fontSize: AppTheme.textMD * AppTheme.textScale(context),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppTheme.spaceSM * AppTheme.spaceScale(context),
                    vertical: AppTheme.spaceSM * AppTheme.spaceScale(context),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                  ),
                ),
                onPressed: () async {
                  final dir = await FilePicker.platform.getDirectoryPath();
                  if (dir != null) {
                    setState(() => _selectedDir = dir);
                  }
                },
              ),
            ],
          ),
          if (_showQueryInfo)
            StreamBuilder(
              stream: UrlQueryOutput.rustSignalStream,
              builder: (context, snapshot) {
                final signalPack = snapshot.data;
                if (signalPack == null) {
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
                        )
                      ),
                      const SizedBox(width: AppTheme.spaceSM),
                      Text(
                        "Querying info...",
                        style: textTheme.bodySmall?.copyWith(
                          color: Colors.green.shade600,
                        ),
                      ),
                    ],
                  );
                }
                final urlQuery = signalPack.message as UrlQueryOutput;
                if (!_queryFinished && !urlQuery.error) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    setState(() {
                      _queryFinished = true;
                      _nameController.text = urlQuery.isWebpage ? "index.html" : urlQuery.name;
                    });
                  });
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: urlQuery.error
                  ? [ 
                      const SizedBox(height: AppTheme.spaceSM),
                      Text(
                        "✖ URL can't be reached",
                        style: textTheme.bodySmall?.copyWith(
                          color: Colors.red.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ]
                  : [
                      const SizedBox(height: AppTheme.spaceSM),
                      TextField(
                        controller: _nameController,
                        onSubmitted: (_) => _handleSubmit(),
                        decoration: InputDecoration(
                          labelText: "Filename",
                          labelStyle: textTheme.bodyMedium,
                          floatingLabelStyle: textTheme.bodySmall?.copyWith(
                            color: colors.primary,
                          ),
                          hintText: "download.bin",
                          hintStyle: textTheme.bodyMedium,
                          border: const OutlineInputBorder(
                            borderRadius:
                                BorderRadius.all(Radius.circular(AppTheme.radiusMD)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppTheme.spaceSM,
                            vertical: AppTheme.spaceSM,
                          ),
                        ),
                        style: textTheme.bodyMedium,
                      ),
                      const SizedBox(height: AppTheme.spaceSM),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (urlQuery.isWebpage)
                            Row(
                              children: [
                                Text(
                                  "RETURNED WEBPAGE",
                                  style: textTheme.bodySmall?.copyWith(color: colors.error),
                                ),
                                const SizedBox(width: AppTheme.spaceMD),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() {
                                      _isQueryingYtdl = true;
                                    });
                                    QueryYtdl(url: _urlController.text.trim()).sendSignalToRust();
                                  },
                                  child: const Text("YTDL"),
                                ),
                              ],
                            ),
                          Text(
                            "Filesize: ${urlQuery.totalSize != null ? formatBytes(urlQuery.totalSize!.toInt()) : '?'}",
                            style: textTheme.bodySmall,
                          ),
                        ],
                      )
                    ],
                );
              },
            ),
        ],
      ),
    );
  }
}
