import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nadekodon/utils/logger.dart';

/// GitHub repository information
const String _githubOwner = 'izaz4141';
const String _githubRepo = 'nadekodon-rs';
const String _appImageName = 'nadekodon-linux-x64.AppImage';

class VersionInfo {
  final String version;
  final String downloadUrl;
  final String releaseNotes;
  final String publishedAt;

  VersionInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.publishedAt,
  });

  factory VersionInfo.fromJson(Map<String, dynamic> json) {
    String? downloadUrl;
    if (json['assets'] != null) {
      for (var asset in json['assets']) {
        if (asset['name'] == _appImageName) {
          downloadUrl = asset['browser_download_url'];
          break;
        }
      }
    }

    return VersionInfo(
      version: json['tag_name'] ?? '',
      downloadUrl: downloadUrl ?? '',
      releaseNotes: json['body'] ?? '',
      publishedAt: json['published_at'] ?? '',
    );
  }
}

Future<VersionInfo?> checkForUpdate() async {
  try {
    final url = Uri.parse(
      'https://api.github.com/repos/$_githubOwner/$_githubRepo/releases/latest',
    );

    final response = await http.get(
      url,
      headers: {'Accept': 'application/vnd.github.v3+json'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return VersionInfo.fromJson(data);
    } else {
      log(
        'Failed to fetch latest version: ${response.statusCode}',
        isError: true,
      );
      return null;
    }
  } catch (e) {
    log('Error checking for updates: $e', isError: true);
    return null;
  }
}

Future<String> getCurrentVersion() async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  } catch (e) {
    log('Error getting current version: $e', isError: true);
    return '0.0.0';
  }
}

int compareVersions(String version1, String version2) {
  version1 = version1.replaceFirst(RegExp(r'^v'), '');
  version2 = version2.replaceFirst(RegExp(r'^v'), '');

  final v1Parts = version1.split('.').map(int.tryParse).toList();
  final v2Parts = version2.split('.').map(int.tryParse).toList();

  for (int i = 0; i < v1Parts.length && i < v2Parts.length; i++) {
    final v1 = v1Parts[i] ?? 0;
    final v2 = v2Parts[i] ?? 0;

    if (v1 < v2) return -1;
    if (v1 > v2) return 1;
  }

  if (v1Parts.length < v2Parts.length) return -1;
  if (v1Parts.length > v2Parts.length) return 1;

  return 0;
}

Future<bool> isUpdateAvailable() async {
  final versionInfo = await checkForUpdate();
  if (versionInfo == null) return false;

  final currentVersion = await getCurrentVersion();
  return compareVersions(currentVersion, versionInfo.version) < 0;
}

Future<bool> downloadAndReplaceAppImage(
  VersionInfo versionInfo, {
  Function(double progress)? onProgress,
}) async {
  if (!Platform.isLinux) {
    log('This function only works on Linux', isError: true);
    return false;
  }

  if (versionInfo.downloadUrl.isEmpty) {
    log('No download URL available', isError: true);
    return false;
  }

  try {
    final currentAppImagePath = Platform.environment['APPIMAGE'];
    if (currentAppImagePath == null || currentAppImagePath.isEmpty) {
      log('Not running from AppImage', isError: true);
      return false;
    }

    final tempDir = await getTemporaryDirectory();
    final tempDownloadPath = '${tempDir.path}/$_appImageName.temp';
    final tempFile = File(tempDownloadPath);

    final url = Uri.parse(versionInfo.downloadUrl);
    final request = await http.Client().send(http.Request('GET', url));

    if (request.statusCode != 200) {
      log('Failed to download: ${request.statusCode}', isError: true);
      return false;
    }

    final contentLength = request.contentLength ?? 0;
    var downloadedBytes = 0;

    final sink = tempFile.openWrite();

    await request.stream.forEach((chunk) {
      sink.add(chunk);
      downloadedBytes += chunk.length;

      if (onProgress != null && contentLength > 0) {
        onProgress(downloadedBytes / contentLength);
      }
    });

    await sink.close();

    final currentFile = File(currentAppImagePath);
    final appDir = currentFile.parent;
    final sidecarPath = '${appDir.path}/.$_appImageName.new';
    final sidecarFile = File(sidecarPath);

    await tempFile.copy(sidecarPath);

    await tempFile.delete();

    await Process.run('chmod', ['+x', sidecarPath]);

    final backupPath = '$currentAppImagePath.backup';
    try {
      if (await File(backupPath).exists()) {
        await File(backupPath).delete();
      }
      await currentFile.copy(backupPath);
    } catch (e) {
      log('Warning: Failed to create backup: $e', isError: true);
      // Proceeding anyway as the update is ready
    }

    await sidecarFile.rename(currentAppImagePath);

    log('Update successful! Restarting application...');

    await Process.start(
      currentAppImagePath,
      [],
      mode: ProcessStartMode.detached,
    );

    exit(0);
  } catch (e) {
    log('Error updating AppImage: $e', isError: true);
    return false;
  }
}

Future<bool?> checkAndUpdate({Function(double progress)? onProgress}) async {
  if (!Platform.isLinux) {
    log('Auto-update only supported on Linux AppImage');
    return null;
  }

  final versionInfo = await checkForUpdate();
  if (versionInfo == null) {
    log('Failed to check for updates', isError: true);
    return null;
  }

  final currentVersion = await getCurrentVersion();

  if (compareVersions(currentVersion, versionInfo.version) < 0) {
    log(
      'New version available: ${versionInfo.version} (current: $currentVersion)',
    );
    return await downloadAndReplaceAppImage(
      versionInfo,
      onProgress: onProgress,
    );
  } else {
    log('Already running the latest version: $currentVersion');
    return null;
  }
}
