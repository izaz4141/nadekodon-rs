import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:nadekodon/utils/api_service.dart';

class SystemService {
  static final SystemService _instance = SystemService._internal();
  factory SystemService() => _instance;
  SystemService._internal();

  PackageInfo? _packageInfo;
  final _deviceInfoPlugin = DeviceInfoPlugin();

  Future<void> init() async {
    _packageInfo = await PackageInfo.fromPlatform();
  }

  PackageInfo get packageInfo =>
      _packageInfo ??
      PackageInfo(
        appName: 'Unknown',
        packageName: 'Unknown',
        version: 'Unknown',
        buildNumber: 'Unknown',
      );

  String get versionString =>
      '${packageInfo.version}+${packageInfo.buildNumber}';

  Future<Map<String, String>> getDeviceInfo() async {
    if (kIsWeb) {
      final info = await _deviceInfoPlugin.webBrowserInfo;
      return {
        'Browser': info.browserName.name,
        'Platform': info.platform ?? 'Unknown',
        'User Agent': info.userAgent ?? 'Unknown',
      };
    }

    if (Platform.isAndroid) {
      final info = await _deviceInfoPlugin.androidInfo;
      return {
        'Device': '${info.brand} ${info.model}',
        'OS': 'Android ${info.version.release} (SDK ${info.version.sdkInt})',
        'ID': info.id,
      };
    } else if (Platform.isLinux) {
      final info = await _deviceInfoPlugin.linuxInfo;
      return {
        'Device': Platform.localHostname,
        'OS': '${info.prettyName} (${info.versionId})',
        'ID': info.machineId ?? 'Unknown',
      };
    } else if (Platform.isWindows) {
      final info = await _deviceInfoPlugin.windowsInfo;
      return {
        'Device': info.computerName,
        'OS':
            'Windows ${info.majorVersion}.${info.minorVersion} (Build ${info.buildNumber})',
        'ID': info.deviceId,
      };
    } else if (Platform.isMacOS) {
      final info = await _deviceInfoPlugin.macOsInfo;
      return {
        'Device': info.computerName,
        'OS': 'macOS ${info.majorVersion}.${info.minorVersion}',
        'ID': info.systemGUID ?? 'Unknown',
      };
    }

    return {'OS': kIsWeb ? 'Web' : Platform.operatingSystem};
  }

  Future<String> getYtdlpVersion() async {
    if (kIsWeb) {
      final deps = await APIService.getDepsVersion();
      return deps?['ytdlp'] ?? 'Not found';
    }
    try {
      if (Platform.isAndroid) {
        // Placeholder for Android specific check if needed
        return 'Managed by OS';
      } else {
        if (APIService.isOnline.value) {
          final deps = await APIService.getDepsVersion();
          if (deps != null) return deps['ytdlp']!;
        }

        final result = await Process.run('yt-dlp', ['--version']);
        if (result.exitCode == 0) {
          return result.stdout.toString().trim();
        }
      }
    } catch (_) {}
    return 'Not found';
  }

  Future<String> getFfmpegVersion() async {
    if (kIsWeb) {
      final deps = await APIService.getDepsVersion();
      return deps?['ffmpeg'] ?? 'Not found';
    }
    try {
      if (APIService.isOnline.value) {
        final deps = await APIService.getDepsVersion();
        if (deps != null) return deps['ffmpeg']!;
      }

      final result = await Process.run('ffmpeg', ['-version']);
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final firstLine = output.split('\n').first;
        final versionMatch = RegExp(
          r'ffmpeg version ([\S]+)',
        ).firstMatch(firstLine);
        return versionMatch?.group(1) ?? 'Unknown';
      }
    } catch (_) {}
    return 'Not found';
  }

  int get processorCount => kIsWeb ? 1 : Platform.numberOfProcessors;
}
