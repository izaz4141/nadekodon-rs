import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:nadekodon/utils/api_service.dart';

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
}

class SystemService {
  static final SystemService _instance = SystemService._internal();
  factory SystemService() => _instance;
  SystemService._internal();

  PackageInfo? _packageInfo;
  final _deviceInfoPlugin = DeviceInfoPlugin();
  final ytdlpVersion = ValueNotifier<String?>(null);
  final ffmpegVersion = ValueNotifier<String?>(null);
  final latestAppVersion = ValueNotifier<VersionInfo?>(null);
  final latestYtdlpVersion = ValueNotifier<VersionInfo?>(null);
  final latestFfmpegVersion = ValueNotifier<VersionInfo?>(null);

  Future<void> init() async {
    _packageInfo = await PackageInfo.fromPlatform();

    // Listen to online status to fetch versions accurately
    APIService.isOnline.addListener(_onStatusChanged);
    _onStatusChanged();
  }

  void _onStatusChanged() {
    if (APIService.isOnline.value) {
      fetchVersions();
    }
  }

  PackageInfo get packageInfo =>
      _packageInfo ??
      PackageInfo(
        appName: 'Unknown',
        packageName: 'Unknown',
        version: 'Unknown',
        buildNumber: 'Unknown',
      );

  void refreshVersions() {
    ytdlpVersion.value = null;
    ffmpegVersion.value = null;
    latestAppVersion.value = null;
    latestYtdlpVersion.value = null;
    latestFfmpegVersion.value = null;

    if (APIService.isOnline.value) {
      fetchVersions();
    }
  }

  Future<void> fetchVersions() async {
    // Local tool versions
    ytdlpVersion.value = await APIService.getCurrentVersion('yt-dlp');
    ffmpegVersion.value = await APIService.getCurrentVersion('ffmpeg');

    // Latest app version
    latestAppVersion.value = await APIService.getLatestVersion(
      'izaz4141',
      'nadekodon-rs',
      nightly: true,
    );

    // Latest tool versions
    latestYtdlpVersion.value = await APIService.getLatestVersion(
      'yt-dlp',
      'yt-dlp',
    );
    latestFfmpegVersion.value = await APIService.getLatestVersion(
      'Ffmpeg',
      'Ffmpeg',
      nightly: true,
    );
  }

  String? get serverVersion => APIService.serverVersion.value;

  Future<String?> getServerVersion() => APIService.getServerVersion();

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
