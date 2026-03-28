import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/ui/widgets/app_snackbar.dart';
import 'package:nadekodon/ui/pages/logs_page.dart';
import 'package:nadekodon/ui/pages/licenses_page.dart';
import 'package:nadekodon/ui/widgets/dialog/app_update.dart';
import 'package:nadekodon/utils/settings.dart';
import 'package:nadekodon/utils/updater.dart';
import 'package:nadekodon/utils/system_service.dart';
import 'package:nadekodon/utils/platform_service.dart';
import 'package:nadekodon/utils/api_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class SystemApp extends StatefulWidget {
  const SystemApp({super.key});

  @override
  State<SystemApp> createState() => _SystemAppState();
}

class _SystemAppState extends State<SystemApp> {
  final PackageInfo _packageInfo = SystemService().packageInfo;

  VersionInfo? _latestVersion;
  bool _checkingUpdates = true;
  bool _isUpdating = false;
  double _updateProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _checkForUpdates();
    if (PlatformService().isRemote) {
      SystemService().getServerVersion();
    }
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
    if (kIsWeb || !PlatformService.isDesktop || _latestVersion == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AppUpdateDialog(versionInfo: _latestVersion!),
    );

    if (confirmed != true) return;

    setState(() {
      _isUpdating = true;
      _updateProgress = 0.0;
    });

    bool success = false;

    if (PlatformService.isLinux) {
      success = await downloadAndReplaceAppImage(
        _latestVersion!,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _updateProgress = progress;
          });
        },
      );
    } else if (PlatformService.isWindows) {
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
          if (PlatformService().isRemote) ...[
            SizedBox(height: AppTheme.spaceSM),
            Text(
              'Remote Version: ${APIService.serverVersion.value ?? "Unknown"}',
              style: textTheme.bodyMedium,
            ),
          ],
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
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LogsPage()),
                );
              },
              icon: Icon(
                Icons.article_outlined,
                size: AppTheme.iconMD * AppTheme.iconScale(context),
              ),
              label: Text('View Logs', style: textTheme.bodyMedium),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
              vertical: AppTheme.spaceSM * AppTheme.spaceScale(context),
            ),
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LicensesPage()),
                );
              },
              icon: Icon(
                Icons.description_outlined,
                size: AppTheme.iconMD * AppTheme.iconScale(context),
              ),
              label: Text('Licenses', style: textTheme.bodyMedium),
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

    bool hasUpdate = _latestVersion != null;

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
                  onTap: !kIsWeb && PlatformService.isDesktop && !_isUpdating
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
