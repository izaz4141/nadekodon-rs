import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';
import '../../../utils/settings.dart';
import '../app_snackbar.dart';
import 'package:nadekodon/utils/helper.dart';
import 'package:nadekodon/ui/widgets/view/query_view.dart';
import 'package:nadekodon/ui/widgets/view/query_result_view.dart';
import 'package:nadekodon/ui/widgets/view/ytdlp_view.dart';
import 'package:nadekodon/ui/widgets/dialog/replace_file.dart';

import 'package:nadekodon/src/bindings/bindings.dart';
import 'package:nadekodon/utils/ytdlp_android.dart';

Future<void> showAddDownloadDialog(
  BuildContext context, {
  String? initialUrl,
}) async {
  await showDialog(
    context: context,
    builder: (context) {
      return _AddDownloadDialog(initialUrl: initialUrl);
    },
  );
}

// Wrapper for mobile platforms to maintain dialog behavior
class _AddDownloadDialog extends StatefulWidget {
  final String? initialUrl;

  const _AddDownloadDialog({this.initialUrl});

  @override
  State<_AddDownloadDialog> createState() => _AddDownloadDialogState();
}

class _AddDownloadDialogState extends State<_AddDownloadDialog> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  final _selectedDir = ValueNotifier<String>(
    SettingsManager.downloadFolder.value,
  );

  YtdlFormat? ytdlVideo;
  YtdlFormat? ytdlAudio;
  YtdlQueryOutput? _androidYtdlOutput;

  final _showQueryInfo = ValueNotifier<bool>(false);
  final _queryFinished = ValueNotifier<bool>(false);
  final _isQueryingYtdl = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    // Prioritize initialUrl over clipboard content
    if (widget.initialUrl != null && isUrl(widget.initialUrl!)) {
      _urlController.text = widget.initialUrl!;
    } else {
      _getClipboardContent();
    }
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

  void _onSelectYtdlVideo(YtdlFormat? video) {
    setState(() {
      ytdlVideo = video;
    });
  }

  void _onSelectYtdlAudio(YtdlFormat? audio) {
    setState(() {
      ytdlAudio = audio;
    });
  }

  Future<String> _getUuidFromRust() async {
    final requestId = DateTime.now().millisecondsSinceEpoch.toString();
    RequestNewUuid(requestId: requestId).sendSignalToRust();

    await for (final signal in ReportNewUuid.rustSignalStream) {
      final message = signal.message;
      if (message.requestId == requestId) {
        return message.newUuid;
      }
    }
    throw Exception("Failed to get UUID from Rust");
  }

  Future<void> _onQueryYtdl() async {
    _isQueryingYtdl.value = true;
    if (Platform.isAndroid) {
      final result = await YtDlpAndroid.getVideoInfo(
        _urlController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _androidYtdlOutput = result;
        });
      }
    } else {
      QueryYtdl(url: _urlController.text.trim()).sendSignalToRust();
    }
  }

  void _queryUrl() {
    final url = _urlController.text.trim();
    if (url.isEmpty || !isUrl(url)) {
      AppSnackBar.show(
        context,
        "Please enter a valid URL",
        type: SnackType.error,
      );
      return;
    }
    if (_selectedDir.value.isEmpty) {
      AppSnackBar.show(
        context,
        "Please select a destination folder",
        type: SnackType.error,
      );
      return;
    }
    QueryUrl(url: url).sendSignalToRust();
    _showQueryInfo.value = true;
  }

  Future<void> _handleSubmit() async {
    final url = _urlController.text.trim();
    final name = _nameController.text.trim();
    final destPath = "${_selectedDir.value}/$name";

    if (name.isEmpty) {
      AppSnackBar.show(
        context,
        "Please enter a filename.",
        type: SnackType.error,
      );
      return;
    }
    if (await fileExist(destPath)) {
      if (!mounted) return;
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => const ReplaceFile(),
      );
      final shouldProceed = result ?? false;

      if (shouldProceed == false) {
        return;
      }
    }
    if (!mounted) return;
    Navigator.pop(context);
    DoDownload(
      url: url,
      dest: "${_selectedDir.value}/$name",
      isYtdl: false,
    ).sendSignalToRust();
    AppSnackBar.show(context, "Added download");
  }

  Future<void> _handleYtdlDownload() async {
    final name = _nameController.text.trim();
    final destPath = "${_selectedDir.value}/$name";
    YtdlFormat? vFormat;
    YtdlFormat? aFormat;

    if (name.isEmpty) {
      AppSnackBar.show(
        context,
        "Please enter a filename.",
        type: SnackType.error,
      );
      return;
    }

    if (ytdlVideo != null) {
      vFormat = ytdlVideo;
    }
    if (ytdlAudio != null) {
      aFormat = ytdlAudio;
    }
    if (await fileExist(destPath)) {
      if (!mounted) return;
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => const ReplaceFile(),
      );
      final shouldProceed = result ?? false;

      if (shouldProceed == false) {
        return;
      }
    }

    if (!mounted) return;
    Navigator.pop(context);

    if (Platform.isAndroid) {
      final id = await _getUuidFromRust();
      final url = _urlController.text.trim();

      // Notify Rust to add the download entry
      RequestAddExternalDownload(
        id: id,
        url: url,
        dest: destPath,
      ).sendSignalToRust();

      // Construct options for yt-dlp
      final options = <String, dynamic>{'outtmpl': destPath};

      if (vFormat != null) {
        options['format'] = vFormat.formatId;
        if (aFormat != null) {
          options['format'] = "${vFormat.formatId}+${aFormat.formatId}";
        }
      } else if (aFormat != null) {
        options['format'] = aFormat.formatId;
      }

      // Start download via Python
      YtDlpAndroid.downloadVideo(url, id, options);
    } else {
      DoDownload(
        url: null,
        dest: "${_selectedDir.value}/${_nameController.text}",
        videoFormat: vFormat,
        audioFormat: aFormat,
        isYtdl: true,
      ).sendSignalToRust();
    }
    if (!mounted) return;
    AppSnackBar.show(context, "Added ytdl download");
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusLG),
      ),
      title: Text("New Download", style: textTheme.titleMedium),
      content: _buildInitialView(),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Cancel", style: textTheme.bodyMedium),
        ),
        AnimatedBuilder(
          animation: Listenable.merge([_isQueryingYtdl, _queryFinished]),
          builder: (context, _) {
            return ElevatedButton(
              onPressed: _isQueryingYtdl.value
                  ? _handleYtdlDownload
                  : _queryFinished.value
                  ? _handleSubmit
                  : _queryUrl,
              child: Text(
                _queryFinished.value ? "Download" : "Query",
                style: textTheme.bodyMedium?.copyWith(color: colors.primary),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildInitialView() {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _showQueryInfo,
        _queryFinished,
        _isQueryingYtdl,
        _selectedDir,
      ]),
      builder: (context, _) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: 400 * AppTheme.widthScale(context),
          ),
          child: _buildContent(),
        );
      },
    );
  }

  Widget _buildContent() {
    if (_isQueryingYtdl.value) {
      return YtdlpView(
        nameController: _nameController,
        selectedDir: _selectedDir,
        onDownload: _handleYtdlDownload,
        onVideoChanged: _onSelectYtdlVideo,
        onAudioChanged: _onSelectYtdlAudio,
        directOutput: _androidYtdlOutput,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!_queryFinished.value)
          QueryView(
            urlController: _urlController,
            selectedDir: _selectedDir,
            onQuery: _queryUrl,
          ),
        if (_showQueryInfo.value)
          QueryResultView(
            urlController: _urlController,
            nameController: _nameController,
            selectedDir: _selectedDir,
            queryFinished: _queryFinished,
            isQueryingYtdl: _isQueryingYtdl,
            onDownload: _handleSubmit,
            onQueryYtdl: _onQueryYtdl,
          ),
      ],
    );
  }
}
