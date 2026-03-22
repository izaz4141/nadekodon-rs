import 'package:flutter/material.dart';
import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/ui/widgets/components/section_header.dart';
import 'package:nadekodon/utils/system_service.dart';

class SystemInfo extends StatefulWidget {
  const SystemInfo({super.key});

  @override
  State<SystemInfo> createState() => _SystemInfoState();
}

class _SystemInfoState extends State<SystemInfo> {
  Map<String, String> _deviceData = {};

  @override
  void initState() {
    super.initState();
    _initPlatformState();
  }

  Future<void> _initPlatformState() async {
    final deviceData = await SystemService().getDeviceInfo();

    if (!mounted) return;

    setState(() {
      _deviceData = deviceData;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Column(
      children: [
        SectionHeader(
          title: 'System Info',
          leading: Icon(
            Icons.info_outline_rounded,
            color: colors.onPrimaryContainer,
            size: AppTheme.iconMD * AppTheme.iconScale(context),
          ),
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
            SystemService().processorCount.toString(),
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
