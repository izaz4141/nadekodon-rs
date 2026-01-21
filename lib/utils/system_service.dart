import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:nadekodon/utils/api_service.dart';
import 'package:nadekodon/src/bindings/bindings.dart';

class VersionInfo {
  final String version;
  final String tagName;
  late String? downloadUrl;
  final String releaseNotes;
  final String publishedAt;

  VersionInfo({
    required this.version,
    required this.tagName,
    this.downloadUrl,
    required this.releaseNotes,
    required this.publishedAt,
  });

  factory VersionInfo.fromJson(dynamic json) {
    return VersionInfo(
      version: json['version'] ?? json['tag_name'] ?? '',
      tagName: json['tag_name'] ?? '',
      releaseNotes: json['release_notes'] ?? '',
      publishedAt: json['published_at'] ?? '',
    );
  }
  factory VersionInfo.fromRust(VersionInfoResult result) {
    return VersionInfo(
      version: result.version,
      tagName: result.tagName,
      releaseNotes: result.releaseNotes,
      publishedAt: result.publishedAt,
    );
  }
}

class SystemService {
  static final SystemService _instance = SystemService._internal();
  factory SystemService() => _instance;
  SystemService._internal();

  PackageInfo? _packageInfo;
  // VersionInfo? _latestAppVersion;
  Future<String?>? _localYtdlpVersionFuture;
  Future<VersionInfo?>? _latestYtdlpVersionFuture;
  Future<String?>? _localFfmpegVersionFuture;
  Future<VersionInfo?>? _latestFfmpegVersionFuture;
  final _deviceInfoPlugin = DeviceInfoPlugin();

  Future<void> init() async {
    _packageInfo = await PackageInfo.fromPlatform();
    // latestAppVersion = await APIService.getLatestVersion(
    //   'izaz4141',
    //   'nadekodon-rs',
    //   nightly: true,
    // );
  }

  PackageInfo get packageInfo =>
      _packageInfo ??
      PackageInfo(
        appName: 'Unknown',
        packageName: 'Unknown',
        version: 'Unknown',
        buildNumber: 'Unknown',
      );

  Future<String?> get localYtdlpVersion {
    return _localYtdlpVersionFuture ??= APIService.getCurrentVersion('yt-dlp');
  }

  Future<VersionInfo?> get latestYtdlpVersion {
    return _latestYtdlpVersionFuture ??= APIService.getLatestVersion(
      'yt-dlp',
      'yt-dlp',
    );
  }

  Future<String?> get localFfmpegVersion {
    return _localFfmpegVersionFuture ??= APIService.getCurrentVersion('ffmpeg');
  }

  Future<VersionInfo?> get latestFfmpegVersion {
    return _latestFfmpegVersionFuture ??= APIService.getLatestVersion(
      'Ffmpeg',
      'Ffmpeg',
      nightly: true,
    );
  }

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

  int get processorCount => kIsWeb ? 1 : Platform.numberOfProcessors;
}
