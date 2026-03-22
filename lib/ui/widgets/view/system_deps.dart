import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/ui/widgets/components/section_header.dart';
import 'package:nadekodon/utils/system_service.dart';

class SystemDeps extends StatelessWidget {
  const SystemDeps({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final system = SystemService();

    return Column(
      children: [
        SectionHeader(
          title: 'Dependencies',
          leading: Icon(
            Icons.extension_rounded,
            color: colors.onPrimaryContainer,
            size: AppTheme.iconMD * AppTheme.iconScale(context),
          ),
        ),
        AnimatedBuilder(
          animation: Listenable.merge([
            system.ytdlpVersion,
            system.latestYtdlpVersion,
          ]),
          builder: (context, _) {
            final local = system.ytdlpVersion.value;
            final latest = system.latestYtdlpVersion.value?.version;
            final available = local != null;

            return ListTile(
              leading: Icon(
                Icons.video_library_outlined,
                size: AppTheme.iconMD * AppTheme.iconScale(context),
              ),
              title: Text('yt-dlp', style: textTheme.bodyMedium),
              subtitle: Text(
                _formatWithLatest(local, latest, 'yt-dlp'),
                style: textTheme.bodySmall?.copyWith(
                  color: !available
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
            );
          },
        ),
        AnimatedBuilder(
          animation: Listenable.merge([
            system.ffmpegVersion,
            system.latestFfmpegVersion,
          ]),
          builder: (context, _) {
            final local = system.ffmpegVersion.value;
            final latest = system.latestFfmpegVersion.value?.version;
            final available = local != null;

            return ListTile(
              leading: Icon(
                Icons.movie_outlined,
                size: AppTheme.iconMD * AppTheme.iconScale(context),
              ),
              title: Text('ffmpeg', style: textTheme.bodyMedium),
              subtitle: Text(
                _formatWithLatest(local, latest, 'ffmpeg'),
                style: textTheme.bodySmall?.copyWith(
                  color: !available
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
            );
          },
        ),
      ],
    );
  }
}

String _formatWithLatest(String? local, String? latest, String name) {
  if (local == null) return 'Checking... ($name will not work)';
  return '$local (Latest: ${latest ?? "..."})';
}
