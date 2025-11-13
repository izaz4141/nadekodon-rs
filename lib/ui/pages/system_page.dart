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

  @override
  void initState() {
    super.initState();
    _initPackageInfo();
  }

  Future<void> _initPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _packageInfo = info;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('System'),
      ),
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
                Text(
                  'Nadeko~don',
                  style: textTheme.titleLarge,
                ),
                SizedBox(height: AppTheme.spaceSM),
                Text(
                  'Version: ${_packageInfo.version}+${_packageInfo.buildNumber}',
                  style: textTheme.bodyMedium,
                ),
                SizedBox(height: AppTheme.spaceSM),
                Text(
                  'Author: Glicole',
                  style: textTheme.bodyMedium,
                ),
                SizedBox(height: AppTheme.spaceSM),
                TextButton(
                  onPressed: () => launchUrl(Uri.parse('https://github.com/izaz4141/nadekodon-rs')),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: AppTheme.spaceMD * AppTheme.spaceScale(context),
                    ),
                    child: Column(
                      children: [
                        Icon(FontAwesomeIcons.github,
                            size: AppTheme.iconLG * AppTheme.iconScale(context)),
                        Text('GitHub', style: textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: AppTheme.spaceLG),
                Padding(
                  padding: EdgeInsets.symmetric(vertical: AppTheme.spaceSM * AppTheme.spaceScale(context)),
                  child: ElevatedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => const LogsDialog(),
                      );
                    },
                    icon: Icon(Icons.article_outlined, size: AppTheme.iconMD * AppTheme.iconScale(context)),
                    label: Text('View Logs', style: textTheme.bodyMedium),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: AppTheme.spaceXL),
          const Divider(),
          ListTile(
            title: Text('System Info', style: textTheme.titleMedium),
          ),
          ListTile(
            leading: Icon(Icons.computer_outlined, size: AppTheme.iconMD * AppTheme.iconScale(context)),
            title: Text('Platform', style: textTheme.bodyMedium),
            subtitle: Text(Platform.operatingSystem, style: textTheme.bodySmall),
          ),
          ListTile(
            leading: Icon(Icons.memory_outlined, size: AppTheme.iconMD * AppTheme.iconScale(context)),
            title: Text('Processors', style: textTheme.bodyMedium),
            subtitle: Text(Platform.numberOfProcessors.toString(), style: textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}