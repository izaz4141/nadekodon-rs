import 'package:flutter/material.dart';
import 'package:nadekodon/utils/platform_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:nadekodon/ui/theme/app_theme.dart';

class PermissionDialog extends StatefulWidget {
  const PermissionDialog({super.key});

  @override
  State<PermissionDialog> createState() => _PermissionDialogState();
}

class _PermissionDialogState extends State<PermissionDialog> {
  bool _storageGranted = false;
  bool _notificationGranted = false;
  bool _batteryGranted = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    bool storage = false;
    bool notification = false;
    bool battery = false;

    if (PlatformService.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 30) {
        storage = await Permission.manageExternalStorage.isGranted;
      } else {
        storage = await Permission.storage.isGranted;
      }
      notification = await Permission.notification.isGranted;
      battery = await Permission.ignoreBatteryOptimizations.isGranted;
    }

    if (mounted) {
      setState(() {
        _storageGranted = storage;
        _notificationGranted = notification;
        _batteryGranted = battery;
        _loading = false;
      });
    }
  }

  Future<void> _requestStorage() async {
    if (PlatformService.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 30) {
        await Permission.manageExternalStorage.request();
      } else {
        await Permission.storage.request();
      }
      await _checkPermissions();
    }
  }

  Future<void> _requestNotification() async {
    await Permission.notification.request();
    await _checkPermissions();
  }

  Future<void> _requestBattery() async {
    await Permission.ignoreBatteryOptimizations.request();
    await _checkPermissions();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Permissions Required',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      content: _loading
          ? SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            )
          : SizedBox(
              width: AppTheme.dialogWidth(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PermissionItem(
                    title: 'Storage Access',
                    subtitle: 'Required to save downloaded files',
                    icon: Icons.folder_open,
                    isGranted: _storageGranted,
                    onRequest: _requestStorage,
                  ),
                  SizedBox(
                    height: AppTheme.spaceMD * AppTheme.spaceScale(context),
                  ),
                  _PermissionItem(
                    title: 'Notifications',
                    subtitle: 'Required to show download progress',
                    icon: Icons.notifications_none,
                    isGranted: _notificationGranted,
                    onRequest: _requestNotification,
                  ),
                  SizedBox(
                    height: AppTheme.spaceMD * AppTheme.spaceScale(context),
                  ),
                  _PermissionItem(
                    title: 'Background Execution',
                    subtitle:
                        'Required for downloads to continue in background',
                    icon: Icons.battery_alert,
                    isGranted: _batteryGranted,
                    onRequest: _requestBattery,
                  ),
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _PermissionItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isGranted;
  final VoidCallback onRequest;

  const _PermissionItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isGranted,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListTile(
      leading: Icon(
        icon,
        color: colorScheme.primary,
        size: AppTheme.iconMD * AppTheme.iconScale(context),
      ),
      title: Text(title, style: textTheme.bodyMedium),
      subtitle: Text(
        subtitle,
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: isGranted
          ? Icon(
              Icons.check_circle,
              color: colorScheme.primary,
              size: AppTheme.iconMD * AppTheme.iconScale(context),
            )
          : FilledButton.tonal(
              onPressed: onRequest,
              child: const Text('Grant'),
            ),
      contentPadding: EdgeInsets.zero,
    );
  }
}
