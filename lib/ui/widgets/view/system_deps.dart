import 'package:flutter/material.dart';
import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/ui/widgets/components/section_header.dart';
import 'package:nadekodon/utils/system_service.dart';
import 'package:nadekodon/utils/api_service.dart';
import 'package:url_launcher/url_launcher.dart';

class SystemDeps extends StatefulWidget {
  const SystemDeps({super.key});

  @override
  State<SystemDeps> createState() => _SystemDepsState();
}

class _SystemDepsState extends State<SystemDeps> {
  String _ytdlpVersion = 'Checking...';
  String _ffmpegVersion = 'Checking...';

  @override
  void initState() {
    super.initState();
    _checkVersions();
    APIService.isOnline.addListener(_checkVersions);
  }

  @override
  void dispose() {
    APIService.isOnline.removeListener(_checkVersions);
    super.dispose();
  }

  void _checkVersions() {
    _checkYtdlpVersion();
    _checkFfmpegVersion();
  }

  Future<void> _checkYtdlpVersion() async {
    final version = await SystemService().getYtdlpVersion();
    if (!mounted) return;
    setState(() {
      _ytdlpVersion = version;
    });
  }

  Future<void> _checkFfmpegVersion() async {
    final version = await SystemService().getFfmpegVersion();
    if (!mounted) return;
    setState(() {
      _ffmpegVersion = version;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        const SectionHeader(
          title: 'Dependencies',
          icon: Icons.extension_rounded,
        ),
        ListTile(
          leading: Icon(
            Icons.video_library_outlined,
            size: AppTheme.iconMD * AppTheme.iconScale(context),
          ),
          title: Text('yt-dlp', style: textTheme.bodyMedium),
          subtitle: Text(
            _ytdlpVersion == 'Not found' || _ytdlpVersion == 'Unknown'
                ? 'Not found - yt-dlp downloads will not work'
                : _ytdlpVersion,
            style: textTheme.bodySmall?.copyWith(
              color: _ytdlpVersion == 'Not found' || _ytdlpVersion == 'Unknown'
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.open_in_new),
            iconSize: AppTheme.iconMD * AppTheme.iconScale(context),
            tooltip: "Visit",
            onPressed: () =>
                launchUrl(Uri.parse('https://github.com/yt-dlp/yt-dlp')),
          ),
        ),
        ListTile(
          leading: Icon(
            Icons.movie_outlined,
            size: AppTheme.iconMD * AppTheme.iconScale(context),
          ),
          title: Text('ffmpeg', style: textTheme.bodyMedium),
          subtitle: Text(
            _ffmpegVersion == 'Not found' || _ffmpegVersion == 'Unknown'
                ? 'Not found - yt-dlp downloads will not work'
                : _ffmpegVersion,
            style: textTheme.bodySmall?.copyWith(
              color:
                  _ffmpegVersion == 'Not found' || _ffmpegVersion == 'Unknown'
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.open_in_new),
            iconSize: AppTheme.iconMD * AppTheme.iconScale(context),
            tooltip: "Visit",
            onPressed: () =>
                launchUrl(Uri.parse('https://github.com/FFmpeg/FFmpeg')),
          ),
        ),
      ],
    );
  }
}
