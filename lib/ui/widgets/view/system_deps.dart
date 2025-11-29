import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nadekodon/theme/app_theme.dart';
import 'package:nadekodon/ui/widgets/components/section_header.dart';

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
    _checkYtdlpVersion();
    _checkFfmpegVersion();
  }

  Future<void> _checkYtdlpVersion() async {
    try {
      final result = await Process.run('yt-dlp', ['--version']);
      if (result.exitCode == 0) {
        if (!mounted) return;
        setState(() {
          _ytdlpVersion = result.stdout.toString().trim();
        });
      } else {
        if (!mounted) return;
        setState(() {
          _ytdlpVersion = 'Not found';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ytdlpVersion = 'Not found';
      });
    }
  }

  Future<void> _checkFfmpegVersion() async {
    try {
      final result = await Process.run('ffmpeg', ['-version']);
      if (result.exitCode == 0) {
        // Extract version from first line (e.g., "ffmpeg version 6.0")
        final output = result.stdout.toString();
        final firstLine = output.split('\n').first;
        final versionMatch = RegExp(
          r'ffmpeg version ([\S]+)',
        ).firstMatch(firstLine);
        if (versionMatch != null) {
          if (!mounted) return;
          setState(() {
            _ffmpegVersion = versionMatch.group(1) ?? 'Unknown';
          });
        } else {
          if (!mounted) return;
          setState(() {
            _ffmpegVersion = 'Unknown';
          });
        }
      } else {
        if (!mounted) return;
        setState(() {
          _ffmpegVersion = 'Not found';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ffmpegVersion = 'Not found';
      });
    }
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
        ),
      ],
    );
  }
}
