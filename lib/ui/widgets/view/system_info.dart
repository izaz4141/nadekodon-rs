import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import 'package:flutter/material.dart';
import 'package:nadekodon/theme/app_theme.dart';
import 'package:nadekodon/ui/widgets/components/section_header.dart';

class SystemInfo extends StatefulWidget {
  const SystemInfo({super.key});

  @override
  State<SystemInfo> createState() => _SystemInfoState();
}

class _SystemInfoState extends State<SystemInfo> {
  final _deviceInfoPlugin = DeviceInfoPlugin();
  Map<String, String> _deviceData = {};

  @override
  void initState() {
    super.initState();
    _initPlatformState();
  }

  Future<void> _initPlatformState() async {
    var deviceData = <String, String>{};

    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfoPlugin.androidInfo;
        deviceData = {
          'Device': '${info.brand} ${info.model}',
          'OS Version':
              'Android ${info.version.release} (SDK ${info.version.sdkInt})',
          'ID': info.id,
        };
      } else if (Platform.isLinux) {
        final info = await _deviceInfoPlugin.linuxInfo;
        deviceData = {
          'Device': info.name,
          'OS Version': '${info.prettyName} (${info.versionId})',
          'ID': info.machineId ?? 'Unknown',
        };
      } else if (Platform.isWindows) {
        final info = await _deviceInfoPlugin.windowsInfo;
        deviceData = {
          'Device': info.computerName,
          'OS Version':
              'Windows ${info.majorVersion}.${info.minorVersion} (Build ${info.buildNumber})',
          'ID': info.deviceId,
        };
      }
    } catch (e) {
      deviceData = {'Error': 'Failed to get device info: $e'};
    }

    if (!mounted) return;

    setState(() {
      _deviceData = deviceData;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        const SectionHeader(
          title: 'System Info',
          icon: Icons.info_outline_rounded,
        ),
        if (_deviceData.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: CircularProgressIndicator(),
          )
        else
          ..._deviceData.entries.map(
            (entry) => ListTile(
              leading: Icon(
                _getIconForKey(entry.key),
                size: AppTheme.iconMD * AppTheme.iconScale(context),
              ),
              title: Text(entry.key, style: textTheme.bodyMedium),
              subtitle: Text(entry.value, style: textTheme.bodySmall),
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
      ],
    );
  }

  IconData _getIconForKey(String key) {
    switch (key) {
      case 'Device':
        return Icons.computer_outlined;
      case 'OS Version':
        return Icons.settings_system_daydream_outlined;
      case 'ID':
        return Icons.fingerprint_outlined;
      default:
        return Icons.info_outline;
    }
  }
}
