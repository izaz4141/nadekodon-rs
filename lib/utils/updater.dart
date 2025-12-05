import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:nadekodon/utils/logger.dart';

import 'package:archive/archive_io.dart';

/// GitHub repository information
const String _githubOwner = 'izaz4141';
const String _githubRepo = 'nadekodon-rs';
const String _appImageName = 'nadekodon-linux-x64.AppImage';
const String _windowsZipName = 'nadekodon-windows-x64.zip';

class VersionInfo {
  final Version version;
  final String downloadUrl;
  final String releaseNotes;
  final String publishedAt;

  VersionInfo({
    required this.version,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.publishedAt,
  });

  factory VersionInfo.fromJson(
    Map<String, dynamic> json, {
    Version? overriddenVersion,
  }) {
    String? downloadUrl;
    String targetName = Platform.isWindows ? _windowsZipName : _appImageName;

    if (json['assets'] != null) {
      for (var asset in json['assets']) {
        if (asset['name'] == targetName) {
          downloadUrl = asset['browser_download_url'];
          break;
        }
      }
    }

    // Handle tag_name potentially starting with 'v'
    String tagName = json['tag_name'] ?? '0.0.0';
    if (tagName.startsWith('v')) {
      tagName = tagName.substring(1);
    }

    return VersionInfo(
      version: overriddenVersion ?? Version.parse(tagName),
      downloadUrl: downloadUrl ?? '',
      releaseNotes: json['body'] ?? '',
      publishedAt: json['published_at'] ?? '',
    );
  }
}

Future<Version?> _getVersionFromAssets(List<dynamic> assets) async {
  try {
    String? downloadUrl;
    for (var asset in assets) {
      if (asset['name'] == 'pubspec.yaml') {
        downloadUrl = asset['browser_download_url'];
        break;
      }
    }

    if (downloadUrl == null) return null;

    final response = await http.get(Uri.parse(downloadUrl));
    if (response.statusCode != 200) return null;

    final content = response.body;
    final lines = LineSplitter.split(content);
    for (var line in lines) {
      if (line.trim().startsWith('version:')) {
        final versionString = line.split(':')[1].trim();
        return Version.parse(versionString);
      }
    }
  } catch (e) {
    log('Error fetching version from pubspec.yaml: $e', isError: true);
  }
  return null;
}

Future<Version> getCurrentVersion() async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    // pub_semver expects X.Y.Z-prerelease+build
    // We append the build number to ensure it's part of the Version object
    String versionString = packageInfo.version;
    if (packageInfo.buildNumber.isNotEmpty) {
      versionString += '+${packageInfo.buildNumber}';
    }
    return Version.parse(versionString);
  } catch (e) {
    log('Error getting current version: $e', isError: true);
    return Version(0, 0, 0);
  }
}

bool isNewerThan(Version newVersion, Version currentVersion) {
  // If major, minor, or patch are different, standard SemVer takes precedence.
  // e.g. 0.1.2 > 0.1.1-nightly
  if (newVersion.major != currentVersion.major ||
      newVersion.minor != currentVersion.minor ||
      newVersion.patch != currentVersion.patch) {
    return newVersion > currentVersion;
  }

  int? newBuild = _extractBuildNumber(newVersion);
  int? currentBuild = _extractBuildNumber(currentVersion);

  if (newBuild != null && currentBuild != null) {
    return newBuild > currentBuild;
  }

  // Fallback to standard SemVer if build numbers are missing
  return newVersion > currentVersion;
}

int? _extractBuildNumber(Version version) {
  if (version.build.isEmpty) return null;
  final firstBuild = version.build.first;
  if (firstBuild is int) {
    return firstBuild;
  }
  if (firstBuild is String) {
    return int.tryParse(firstBuild);
  }
  return null;
}

Future<VersionInfo?> checkForUpdate({bool checkNightly = false}) async {
  try {
    final currentVersion = await getCurrentVersion();
    final isNightly = currentVersion.isPreRelease;

    if (isNightly || checkNightly) {
      final url = Uri.parse(
        'https://api.github.com/repos/$_githubOwner/$_githubRepo/releases',
      );
      final response = await http.get(
        url,
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode == 200) {
        final List<dynamic> releases = jsonDecode(response.body);
        VersionInfo? newestVersion;

        for (var release in releases) {
          try {
            Version? assetVersion;
            if (release['assets'] != null) {
              assetVersion = await _getVersionFromAssets(release['assets']);
            }

            final info = VersionInfo.fromJson(
              release,
              overriddenVersion: assetVersion,
            );
            if (isNewerThan(info.version, currentVersion)) {
              if (newestVersion == null ||
                  isNewerThan(info.version, newestVersion.version)) {
                newestVersion = info;
              }
            }
          } catch (e) {
            continue;
          }
        }
        return newestVersion;
      } else {
        log('Failed to fetch releases: ${response.statusCode}', isError: true);
        return null;
      }
    } else {
      final url = Uri.parse(
        'https://api.github.com/repos/$_githubOwner/$_githubRepo/releases/latest',
      );

      final response = await http.get(
        url,
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        Version? assetVersion;
        if (data['assets'] != null) {
          assetVersion = await _getVersionFromAssets(data['assets']);
        }

        final info = VersionInfo.fromJson(
          data,
          overriddenVersion: assetVersion,
        );
        if (isNewerThan(info.version, currentVersion)) {
          return info;
        }
        return null;
      } else {
        log(
          'Failed to fetch latest version: ${response.statusCode}',
          isError: true,
        );
        return null;
      }
    }
  } catch (e) {
    log('Error checking for updates: $e', isError: true);
    return null;
  }
}

Future<bool> isUpdateAvailable() async {
  final versionInfo = await checkForUpdate();
  if (versionInfo == null) return false;

  final currentVersion = await getCurrentVersion();
  return isNewerThan(versionInfo.version, currentVersion);
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

Future<bool> downloadAndReplaceWindows(
  VersionInfo versionInfo, {
  Function(double progress)? onProgress,
}) async {
  if (!Platform.isWindows) {
    log('This function only works on Windows', isError: true);
    return false;
  }

  if (versionInfo.downloadUrl.isEmpty) {
    log('No download URL available', isError: true);
    return false;
  }

  try {
    final tempDir = await getTemporaryDirectory();
    final tempDownloadPath = '${tempDir.path}/update.zip';
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

    // Extract zip
    final bytes = await tempFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final currentDir = File(Platform.resolvedExecutable).parent;

    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        final targetPath = '${currentDir.path}/$filename';
        final targetFile = File(targetPath);

        if (await targetFile.exists()) {
          final oldPath = '$targetPath.old';
          if (await File(oldPath).exists()) {
            await File(oldPath).delete();
          }
          try {
            await targetFile.rename(oldPath);
          } catch (e) {
            log('Could not rename $filename: $e', isError: true);
          }
        }

        await File(targetPath).writeAsBytes(data);
      } else {
        await Directory('${currentDir.path}/$filename').create(recursive: true);
      }
    }

    await tempFile.delete();

    log('Update successful! Restarting application...');

    await Process.start(
      Platform.resolvedExecutable,
      [],
      mode: ProcessStartMode.detached,
    );

    exit(0);
  } catch (e) {
    log('Error updating Windows app: $e', isError: true);
    return false;
  }
}

Future<void> cleanupOldFiles() async {
  if (Platform.isWindows) {
    try {
      final currentDir = File(Platform.resolvedExecutable).parent;
      final entities = currentDir.list(recursive: true);

      await for (final entity in entities) {
        if (entity is File && entity.path.endsWith('.old')) {
          try {
            await entity.delete();
            log('Deleted old file: ${entity.path}');
          } catch (e) {
            // Ignore, might still be locked or something
          }
        }
      }
    } catch (e) {
      log('Error cleaning up old files: $e', isError: true);
    }
  } else if (Platform.isLinux) {
    try {
      final currentAppImagePath = Platform.environment['APPIMAGE'];
      if (currentAppImagePath != null && currentAppImagePath.isNotEmpty) {
        final backupFile = File('$currentAppImagePath.backup');
        if (await backupFile.exists()) {
          await backupFile.delete();
          log('Deleted backup AppImage: ${backupFile.path}');
        }
      }
    } catch (e) {
      log('Error cleaning up backup AppImage: $e', isError: true);
    }
  }
}

Future<bool?> checkAndUpdate({Function(double progress)? onProgress}) async {
  if (!Platform.isLinux && !Platform.isWindows) {
    log('Auto-update only supported on Linux AppImage and Windows');
    return null;
  }

  final versionInfo = await checkForUpdate();
  if (versionInfo == null) {
    log('Failed to check for updates', isError: true);
    return null;
  }

  final currentVersion = await getCurrentVersion();

  if (isNewerThan(versionInfo.version, currentVersion)) {
    log(
      'New version available: ${versionInfo.version} (current: $currentVersion)',
    );
    if (Platform.isLinux) {
      return await downloadAndReplaceAppImage(
        versionInfo,
        onProgress: onProgress,
      );
    } else if (Platform.isWindows) {
      return await downloadAndReplaceWindows(
        versionInfo,
        onProgress: onProgress,
      );
    }
    return false;
  } else {
    log('Already running the latest version: $currentVersion');
    return null;
  }
}
