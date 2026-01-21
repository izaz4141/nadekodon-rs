import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/ui/widgets/components/section_header.dart';
import 'package:nadekodon/utils/system_service.dart';

class SystemDeps extends StatefulWidget {
  const SystemDeps({super.key});

  @override
  State<SystemDeps> createState() => _SystemDepsState();
}

class _SystemDepsState extends State<SystemDeps> {
  String _ytdlpDisplay = 'Checking...';
  String _ffmpegDisplay = 'Checking...';
  bool _ytdlpAvailable = false;
  bool _ffmpegAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadDependencies();
  }

  Future<void> _loadDependencies() async {
    final system = SystemService();

    final ytdlpLocal = await system.localYtdlpVersion;
    final ytdlpLatest = (await system.latestYtdlpVersion)?.version;

    final ffmpegLocal = await system.localFfmpegVersion;
    final ffmpegLatest = (await system.latestFfmpegVersion)?.version;

    if (mounted) {
      setState(() {
        _ytdlpDisplay = _formatWithLatest(ytdlpLocal, ytdlpLatest);
        _ffmpegDisplay = _formatWithLatest(ffmpegLocal, ffmpegLatest);
        _ytdlpAvailable = ytdlpLocal != null;
        _ffmpegAvailable = ffmpegLocal != null;
      });
    }
  }

  @override
  void dispose() {
    super.dispose();
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
            _ytdlpDisplay,
            style: textTheme.bodySmall?.copyWith(
              color: !_ytdlpAvailable
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
            _ffmpegDisplay,
            style: textTheme.bodySmall?.copyWith(
              color: !_ffmpegAvailable
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

String _formatWithLatest(String? local, String? latest) {
  String warning = (local != null) ? '' : 'yt-dlp will not work';
  return '$local (Latest: $latest) $warning';
}
