import 'dart:io';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:nadekodon/theme/app_theme.dart';
import 'package:nadekodon/ui/widgets/app_snackbar.dart';
import 'package:nadekodon/ui/widgets/dialog/view_logs.dart';
import 'package:nadekodon/utils/settings.dart';
import 'package:nadekodon/utils/updater.dart';
import 'package:nadekodon/utils/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:url_launcher/url_launcher.dart';

class SystemApp extends StatefulWidget {
  const SystemApp({super.key});

  @override
  State<SystemApp> createState() => _SystemAppState();
}

class _SystemAppState extends State<SystemApp> {
  PackageInfo _packageInfo = PackageInfo(
    appName: 'Unknown',
    packageName: 'Unknown',
    version: 'Unknown',
    buildNumber: 'Unknown',
  );

  VersionInfo? _latestVersion;
  bool _checkingUpdates = true;
  bool _isUpdating = false;
  double _updateProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _initPackageInfo();
    _checkForUpdates();
    SettingsManager.checkNightly.addListener(_checkForUpdates);
  }

  @override
  void dispose() {
    SettingsManager.checkNightly.removeListener(_checkForUpdates);
    super.dispose();
  }

  Future<void> _checkForUpdates() async {
    final versionInfo = await checkForUpdate(
      checkNightly: SettingsManager.checkNightly.value,
    );
    if (!mounted) return;
    setState(() {
      _latestVersion = versionInfo;
      _checkingUpdates = false;
    });
  }

  Future<void> _performUpdate() async {
    if (Platform.isAndroid || _latestVersion == null) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Update Available',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        content: Text(
          'A new version (${_latestVersion!.version}) is available.\n'
          'The app will download and install the update, then restart automatically.\n'
          'Do you want to continue?',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Update',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isUpdating = true;
      _updateProgress = 0.0;
    });

    bool success = false;

    if (Platform.isLinux) {
      success = await downloadAndReplaceAppImage(
        _latestVersion!,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _updateProgress = progress;
          });
        },
      );
    } else if (Platform.isWindows) {
      success = await downloadAndReplaceWindows(
        _latestVersion!,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _updateProgress = progress;
          });
        },
      );
    }

    if (!mounted) return;

    if (!success) {
      setState(() {
        _isUpdating = false;
      });

      if (!mounted) return;
      AppSnackBar.show(
        context,
        'Failed to update. Please try again.',
        type: SnackType.error,
      );
    }
  }

  Future<void> _initPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _packageInfo = info;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Column(
        children: [
          SizedBox(
            height: AppTheme.iconXXL * 2 * AppTheme.iconScale(context),
            child: Image.asset('assets/icons/nadeko-don-1024.png'),
          ),
          SizedBox(height: AppTheme.spaceLG),
          Text('Nadeko~don', style: textTheme.titleLarge),
          SizedBox(height: AppTheme.spaceSM),
          _buildVersionInfo(context, textTheme),
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
          SizedBox(height: AppTheme.spaceSM),
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
    );
  }

  Widget _buildVersionInfo(BuildContext context, TextTheme textTheme) {
    if (_checkingUpdates) {
      return Text(
        'Version: ${_packageInfo.version}+${_packageInfo.buildNumber}',
        style: textTheme.bodyMedium,
      );
    }

    bool hasUpdate = false;
    try {
      if (_latestVersion != null) {
        final currentVer = Version.parse(
          '${_packageInfo.version}+${_packageInfo.buildNumber}',
        );
        hasUpdate = isNewerThan(_latestVersion!.version, currentVer);
      }
    } catch (e) {
      log(e.toString(), isError: true);
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Version: ${_packageInfo.version}+${_packageInfo.buildNumber}',
              style: textTheme.bodyMedium,
            ),
            if (hasUpdate) ...[
              SizedBox(width: AppTheme.spaceSM),
              Tooltip(
                message: 'Latest version: ${_latestVersion!.version}',
                child: InkWell(
                  onTap: !Platform.isAndroid && !_isUpdating
                      ? _performUpdate
                      : null,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppTheme.spaceSM,
                      vertical: AppTheme.spaceXS,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isUpdating)
                          SizedBox(
                            width:
                                AppTheme.iconSM * AppTheme.iconScale(context),
                            height:
                                AppTheme.iconSM * AppTheme.iconScale(context),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value: _updateProgress > 0
                                  ? _updateProgress
                                  : null,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          )
                        else
                          Icon(
                            Icons.info_outline,
                            size: AppTheme.iconSM * AppTheme.iconScale(context),
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        SizedBox(width: AppTheme.spaceXS),
                        Text(
                          _isUpdating ? 'Updating...' : 'Update Available',
                          style: textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
