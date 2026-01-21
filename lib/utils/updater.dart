import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nadekodon/utils/api_service.dart';
import 'package:nadekodon/utils/logger.dart';
import 'package:nadekodon/utils/app_lifecycle.dart';
import 'package:nadekodon/utils/single_instance.dart';
import 'package:nadekodon/utils/system_service.dart';

import 'package:archive/archive_io.dart';

/// GitHub repository information
const String _githubOwner = 'izaz4141';
const String _githubRepo = 'nadekodon-rs';
const String _appImageName = 'nadekodon-linux-x64.AppImage';
const String _windowsZipName = 'nadekodon-windows-x64.zip';

Future<VersionInfo?> checkForUpdate({bool checkNightly = false}) async {
  try {
    final currentVersion = SystemService().packageInfo;
    final isNightly = currentVersion.version.contains("-");
    final shouldCheckNightly = isNightly || checkNightly;

    final latestVersion = await APIService.getLatestVersion(
      _githubOwner,
      _githubRepo,
      nightly: shouldCheckNightly,
      atomic: false,
    );
    if (latestVersion == null) {
      return null;
    }

    final compareResult = await APIService.compareVersions([
      latestVersion.version,
      "${currentVersion.version}+${currentVersion.buildNumber}",
    ]);
    if (compareResult == latestVersion.version) {
      String targetName = '';
      if (!kIsWeb) {
        targetName = Platform.isWindows ? _windowsZipName : _appImageName;
      }
      String downloadUrl =
          'https://github.com/$_githubOwner/$_githubRepo/releases/download/${latestVersion.tagName}/$targetName';

      return VersionInfo(
        version: latestVersion.version,
        tagName: latestVersion.tagName,
        downloadUrl: downloadUrl,
        releaseNotes: latestVersion.releaseNotes,
        publishedAt: latestVersion.publishedAt,
      );
    }

    return null;
  } catch (e) {
    log('Error checking for updates: $e', isError: true);
    return null;
  }
}

Future<bool> downloadAndReplaceAppImage(
  VersionInfo versionInfo, {
  Function(double progress)? onProgress,
}) async {
  if (!Platform.isLinux) {
    log('This function only works on Linux', isError: true);
    return false;
  }

  if (versionInfo.downloadUrl != null) {
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

    final url = Uri.parse(versionInfo.downloadUrl!);
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

    // Release the single instance lock so the new process can start
    await SingleInstance.dispose();

    await Process.start(
      currentAppImagePath,
      [],
      mode: ProcessStartMode.detached,
    );

    await closeApp();
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

  if (versionInfo.downloadUrl != null) {
    log('No download URL available', isError: true);
    return false;
  }

  try {
    final tempDir = await getTemporaryDirectory();
    final tempDownloadPath = '${tempDir.path}/update.zip';
    final tempFile = File(tempDownloadPath);

    final url = Uri.parse(versionInfo.downloadUrl!);
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

    // Release the single instance lock so the new process can start
    await SingleInstance.dispose();

    await Process.start(
      Platform.resolvedExecutable,
      [],
      mode: ProcessStartMode.detached,
    );

    await closeApp();
    exit(0);
  } catch (e) {
    log('Error updating Windows app: $e', isError: true);
    return false;
  }
}

Future<void> cleanupOldFiles() async {
  if (kIsWeb) return;

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
  if (kIsWeb || (!Platform.isLinux && !Platform.isWindows)) {
    log('Auto-update only supported on Linux AppImage and Windows');
    return null;
  }

  final versionInfo = await checkForUpdate();
  if (versionInfo == null) {
    log('Failed to check for updates', isError: true);
    return null;
  }

  final currentVersion = await PackageInfo.fromPlatform();
  final latestVersion = versionInfo.version;

  if (latestVersion !=
      "${currentVersion.version}+${currentVersion.buildNumber}") {
    log(
      'New version available: ${versionInfo.version} (current: ${currentVersion.version}+${currentVersion.buildNumber})',
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
