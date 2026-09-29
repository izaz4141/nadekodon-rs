import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/ui/widgets/app_snackbar.dart';
import 'package:nadekodon/ui/widgets/dialog/replace_file.dart';
import 'package:nadekodon/ui/widgets/view/query_result_view.dart';
import 'package:nadekodon/ui/widgets/view/query_view.dart';
import 'package:nadekodon/ui/widgets/view/ytdlp_view.dart';
import 'package:nadekodon/utils/bridge_service.dart';
import 'package:nadekodon/utils/helper.dart';
import 'package:nadekodon/utils/io_service.dart';
import 'package:nadekodon/utils/platform_service.dart';
import 'package:nadekodon/utils/settings.dart';

Future<void> showAddDownloadDialog(
  BuildContext context, {
  String? initialUrl,
  String? cookie,
  String? userAgent,
  String? referer,
  bool forceLocal = false,
  bool autoQuery = false,
}) async {
  await showDialog(
    context: context,
    builder: (context) {
      return _AddDownloadDialog(
        initialUrl: initialUrl,
        cookie: cookie,
        userAgent: userAgent,
        referer: referer,
        forceLocal: forceLocal,
        autoQuery: autoQuery,
      );
    },
  );
}

// Wrapper for mobile platforms to maintain dialog behavior
class _AddDownloadDialog extends StatefulWidget {
  final String? initialUrl;
  final String? cookie;
  final String? userAgent;
  final String? referer;
  final bool forceLocal;
  final bool autoQuery;

  const _AddDownloadDialog({
    this.initialUrl,
    this.cookie,
    this.userAgent,
    this.referer,
    this.forceLocal = false,
    this.autoQuery = false,
  });

  @override
  State<_AddDownloadDialog> createState() => _AddDownloadDialogState();
}

class _AddDownloadDialogState extends State<_AddDownloadDialog> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();

  /// Where this download goes. Starts from the configured destination and can
  /// be overridden per download by [DirChoose], which resolves category paths
  /// against [SettingsManager.downloadFolder].
  final _selectedDir = ValueNotifier<String>(
    SettingsManager.downloadFolder.value,
  );
  final _selectedCategory = ValueNotifier<String?>(null);

  YtdlFormat? ytdlVideo;
  YtdlFormat? ytdlAudio;
  YtdlQueryOutput? _ytdlOutput;
  UrlQueryOutput? _urlOutput;

  final _showQueryInfo = ValueNotifier<bool>(false);
  final _queryFinished = ValueNotifier<bool>(false);
  final _isQueryingYtdl = ValueNotifier<bool>(false);

  /// Resolved once so [_queryUrl] never reads a half filled destination.
  late final Future<void> _destDirReady;

  @override
  void initState() {
    super.initState();
    _destDirReady = _resolveDestDir();
    // Prioritize initialUrl over clipboard content
    if (widget.initialUrl != null && isValidDownloadInput(widget.initialUrl!)) {
      _urlController.text = widget.initialUrl!;
      if (widget.autoQuery) _scheduleAutoQuery();
    } else {
      _getClipboardContent();
    }
  }

  /// Queries the source the dialog was opened with, so the OS file association
  /// and a deep link do not need a second tap.
  ///
  /// Deferred to after the first frame because [BridgeService.queryUrl] reports
  /// through the context.
  void _scheduleAutoQuery() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _queryUrl();
    });
  }

  Future<void> _getClipboardContent() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    final clipboardText = clipboardData?.text;
    if (clipboardText != null && isValidDownloadInput(clipboardText)) {
      setState(() {
        _urlController.text = clipboardText;
      });
    }
  }

  /// Picking a `.torrent` reads from the local disk, so it only makes sense
  /// when the bridge talks to the local engine.
  bool get _canPickTorrent => !PlatformService().isRemote;

  Future<void> _browseTorrent() async {
    if (!_canPickTorrent) {
      AppSnackBar.show(
        context,
        "Opening local torrent files is not supported in remote mode",
        type: SnackType.error,
      );
      return;
    }

    final path = await IOServiceFactory.create().pickFile(
      allowedExtensions: ['torrent'],
      dialogTitle: "Open .torrent file",
    );
    if (path == null || !mounted) return;

    setState(() {
      _urlController.text = path;
    });
    _queryUrl();
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

  Future<void> _onQueryYtdl() async {
    _isQueryingYtdl.value = true;
    setState(() {
      _ytdlOutput = null;
    });

    YtdlQueryOutput? result;

    result = await BridgeService.queryYtdl(
      url: _urlController.text.trim(),
      forceLocal: widget.forceLocal,
    );

    if (mounted) {
      setState(() {
        _ytdlOutput = result;
      });
    }
  }

  /// Where the download lands depends on which engine runs it. A local engine
  /// needs a folder on this machine, and the configured one can name a folder
  /// that only exists on the server, so it is verified before it is used.
  Future<void> _resolveDestDir() async {
    if (kIsWeb) return;
    final io = IOServiceFactory.create();

    if (widget.forceLocal) {
      final configured = await io.getCurrentDownloadDir();
      final local =
          configured.isNotEmpty && await io.directoryExists(configured);
      final dir = local ? configured : await io.getDownloadsDir();
      if (mounted) _selectedDir.value = dir;
      return;
    }

    // A remote engine downloads on the server, where the local Downloads
    // folder means nothing.
    if (_selectedDir.value.isNotEmpty || PlatformService().isRemote) return;
    final dir = await io.getDownloadsDir();
    if (mounted) _selectedDir.value = dir;
  }

  void _queryUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || !isValidDownloadInput(url)) {
      AppSnackBar.show(
        context,
        "Please enter a valid URL",
        type: SnackType.error,
      );
      return;
    }
    await _destDirReady;
    if (!mounted) return;
    if (_selectedDir.value.isEmpty) {
      AppSnackBar.show(
        context,
        "Please select a destination folder",
        type: SnackType.error,
      );
      return;
    }

    _showQueryInfo.value = true;
    setState(() {
      _urlOutput = null;
    });

    UrlQueryOutput? result;

    result = await BridgeService.queryUrl(
      url: url,
      cookie: widget.cookie,
      userAgent: widget.userAgent,
      referer: widget.referer,
      forceLocal: widget.forceLocal,
    );

    if (mounted) {
      setState(() {
        _urlOutput = result;
      });
    }
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

    await BridgeService.addDownload(
      url: url,
      dest: "${_selectedDir.value}/$name",
      isYtdl: false,
      cookie: widget.cookie,
      userAgent: widget.userAgent,
      referer: widget.referer,
      category: _selectedCategory.value,
      forceLocal: widget.forceLocal,
    );
    if (!mounted) return;
    AppSnackBar.show(
      context,
      widget.forceLocal ? "Added local download" : "Added download",
    );
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

    BridgeService.addDownload(
      url: null,
      dest: "${_selectedDir.value}/${_nameController.text}",
      videoFormat: vFormat,
      audioFormat: aFormat,
      isYtdl: true,
      referer: _urlController.text.trim(),
      category: _selectedCategory.value,
    );

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
        _selectedCategory,
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
        selectedCategory: _selectedCategory,
        onDownload: _handleYtdlDownload,
        onVideoChanged: _onSelectYtdlVideo,
        onAudioChanged: _onSelectYtdlAudio,
        output: _ytdlOutput,
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!_queryFinished.value)
          QueryView(
            urlController: _urlController,
            selectedDir: _selectedDir,
            selectedCategory: _selectedCategory,
            onQuery: _queryUrl,
            onBrowseTorrent: _canPickTorrent ? _browseTorrent : null,
          ),
        if (_showQueryInfo.value)
          QueryResultView(
            urlController: _urlController,
            nameController: _nameController,
            selectedDir: _selectedDir,
            selectedCategory: _selectedCategory,
            queryFinished: _queryFinished,
            isQueryingYtdl: _isQueryingYtdl,
            onDownload: _handleSubmit,
            onQueryYtdl: _onQueryYtdl,
            output: _urlOutput,
          ),
      ],
    );
  }
}
