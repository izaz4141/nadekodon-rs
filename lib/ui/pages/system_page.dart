import 'dart:io';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:nadekodon/ui/widgets/dialog/view_logs.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:nadekodon/theme/app_theme.dart';

class SystemPage extends StatefulWidget {
  const SystemPage({super.key});

  @override
  State<SystemPage> createState() => _SystemPageState();
}

class _SystemPageState extends State<SystemPage> {
  PackageInfo _packageInfo = PackageInfo(
    appName: 'Unknown',
    packageName: 'Unknown',
    version: 'Unknown',
    buildNumber: 'Unknown',
  );

  String _ytdlpVersion = 'Checking...';
  String _ffmpegVersion = 'Checking...';

  @override
  void initState() {
    super.initState();
    _initPackageInfo();
    _checkYtdlpVersion();
    _checkFfmpegVersion();
  }

  Future<void> _initPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _packageInfo = info;
    });
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
    final isDesktop = AppTheme.isDesktop(context);

    return Scaffold(
      appBar: isDesktop
          ? AppBar(title: Text("System", style: textTheme.titleLarge))
          : null,
      body: ListView(
        children: [
          SizedBox(height: AppTheme.spaceXL),
          Center(
            child: Column(
              children: [
                SizedBox(
                  height: AppTheme.iconXXL * 2 * AppTheme.iconScale(context),
                  child: Image.asset('assets/icons/nadeko-don.png'),
                ),
                SizedBox(height: AppTheme.spaceLG),
                Text('Nadeko~don', style: textTheme.titleLarge),
                SizedBox(height: AppTheme.spaceSM),
                Text(
                  'Version: ${_packageInfo.version}+${_packageInfo.buildNumber}',
                  style: textTheme.bodyMedium,
                ),
                SizedBox(height: AppTheme.spaceSM),
                Text('Author: Glicole', style: textTheme.bodyMedium),
                SizedBox(height: AppTheme.spaceSM),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse('https://github.com/izaz4141/nadekodon-rs'),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: AppTheme.spaceMD * AppTheme.spaceScale(context),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          FontAwesomeIcons.github,
                          size: AppTheme.iconLG * AppTheme.iconScale(context),
                        ),
                        Text('GitHub', style: textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: AppTheme.spaceLG),
                Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: AppTheme.spaceSM * AppTheme.spaceScale(context),
                  ),
                  child: ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => const LogsDialog(),
                      );
                    },
                    icon: Icon(
                      Icons.article_outlined,
                      size: AppTheme.iconMD * AppTheme.iconScale(context),
                    ),
                    label: Text('View Logs', style: textTheme.bodyMedium),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: AppTheme.spaceXL),
          const Divider(),
          ListTile(title: Text('System Info', style: textTheme.titleMedium)),
          ListTile(
            leading: Icon(
              Icons.computer_outlined,
              size: AppTheme.iconMD * AppTheme.iconScale(context),
            ),
            title: Text('Platform', style: textTheme.bodyMedium),
            subtitle: Text(
              Platform.operatingSystem,
              style: textTheme.bodySmall,
            ),
          ),
          ListTile(
            leading: Icon(
              Icons.memory_outlined,
              size: AppTheme.iconMD * AppTheme.iconScale(context),
            ),
            title: Text('Processors', style: textTheme.bodyMedium),
            subtitle: Text(
              Platform.numberOfProcessors.toString(),
              style: textTheme.bodySmall,
            ),
          ),
          const Divider(),
          ListTile(title: Text('Dependencies', style: textTheme.titleMedium)),
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
                color:
                    _ytdlpVersion == 'Not found' || _ytdlpVersion == 'Unknown'
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
      ),
    );
  }
}
