import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:collection/collection.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:nadekodon/src/bindings/bindings.dart';
import 'package:nadekodon/utils/logger.dart';
import 'package:nadekodon/utils/platform_service.dart';
import 'package:nadekodon/utils/settings.dart';
import 'package:nadekodon/utils/io_service.dart';

String? _cachedDeviceId;

Future<String> _getDeviceId() async {
  if (_cachedDeviceId != null) return _cachedDeviceId!;

  final deviceInfo = DeviceInfoPlugin();
  String deviceId = '';

  if (Platform.isAndroid) {
    final androidInfo = await deviceInfo.androidInfo;
    deviceId = androidInfo.id;
  } else if (Platform.isLinux) {
    final linuxInfo = await deviceInfo.linuxInfo;
    deviceId = linuxInfo.id;
  } else if (Platform.isWindows) {
    final windowsInfo = await deviceInfo.windowsInfo;
    deviceId = windowsInfo.deviceId;
  }

  _cachedDeviceId = deviceId;
  return deviceId;
}

Future<String> x0(String input) async {
  final deviceId = await _getDeviceId();
  final id = DateTime.now().microsecondsSinceEpoch.toString();

  final stream = CreateTaggingResponse.rustSignalStream.where(
    (signal) => signal.message.id == id,
  );

  CreateTaggingRequest(
    id: id,
    name: input,
    description: deviceId,
  ).sendSignalToRust();

  final signal = await stream.first;
  return signal.message.success;
}

Future<String> d0(String input) async {
  final deviceId = await _getDeviceId();
  final id = DateTime.now().microsecondsSinceEpoch.toString();

  final stream = PutTaggingResponse.rustSignalStream.where(
    (signal) => signal.message.id == id,
  );

  PutTaggingRequest(id: id, name: input, tag: deviceId).sendSignalToRust();

  final signal = await stream.first;
  return signal.message.success;
}

enum DownloadStatus {
  queued,
  running,
  seeding,
  stalledDL,
  stalledUP,
  paused,
  completed,
  cancelled,
  failed,
}

DownloadStatus parseDownloadStatus(String state) {
  final s = state.toLowerCase();
  if (s.contains('error')) return DownloadStatus.failed;
  switch (s) {
    case 'queued':
      return DownloadStatus.queued;
    case 'running':
      return DownloadStatus.running;
    case 'seeding':
      return DownloadStatus.seeding;
    case 'stalleddl':
      return DownloadStatus.stalledDL;
    case 'stalledup':
      return DownloadStatus.stalledUP;
    case 'paused':
      return DownloadStatus.paused;
    case 'completed':
      return DownloadStatus.completed;
    case 'cancelled':
      return DownloadStatus.cancelled;
    case 'error':
      return DownloadStatus.failed;
    default:
      return DownloadStatus.failed;
  }
}

class DownloadItem {
  final String id;
  final String downloadType;
  final String name;
  final String dest;
  final int downloaded;
  final int? total;
  final DownloadStatus status;
  final double dspeed;
  final double? uspeed;
  final String? referer;

  const DownloadItem({
    required this.id,
    required this.downloadType,
    required this.name,
    required this.dest,
    required this.downloaded,
    required this.total,
    required this.status,
    required this.dspeed,
    this.uspeed,
    this.referer,
  });

  double get progress =>
      (total != null && total! > 0) ? downloaded / total! : 0.0;
}

String formatBytes(int bytes) {
  const suffixes = ["B", "KB", "MB", "GB"];
  double size = bytes.toDouble();
  int i = 0;
  while (size >= 1024 && i < suffixes.length - 1) {
    size /= 1024;
    i++;
  }
  return "${size.toStringAsFixed(1)} ${suffixes[i]}";
}

String snakeToCamel(String input) {
  return input.split('_').mapIndexed((i, word) {
    if (i == 0) return word;
    return word[0].toUpperCase() + word.substring(1);
  }).join();
}

String camelToSnake(String input) {
  return input
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match[1]}_${match[2]!.toLowerCase()}',
      )
      .toLowerCase();
}

bool isUrl(String url) {
  if (url.toLowerCase().startsWith('magnet:?')) return true;
  final regex = RegExp(
    r'^(?:http|https)://'
    r'(?:(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.)+[A-Z]{2,6}\.?|'
    r'localhost|'
    r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})'
    r'(?::\d+)?'
    r'(?:/?|[/?]\S+)$',
    caseSensitive: false,
  );
  return regex.hasMatch(url);
}

Future<bool> fileExist(String path) async {
  if (kIsWeb) return false;
  final type = await FileSystemEntity.type(path);
  return type != FileSystemEntityType.notFound;
}

Future<ResultType> openFile(String filePath) async {
  if (kIsWeb) return ResultType.error;
  final file = File(filePath);

  if (!await file.exists()) {
    return ResultType.fileNotFound;
  }

  try {
    if (PlatformService.isAndroid && filePath.toLowerCase().endsWith('.apk')) {
      if (!await Permission.requestInstallPackages.isGranted) {
        final status = await Permission.requestInstallPackages.request();
        if (!status.isGranted) {
          return ResultType.permissionDenied;
        }
      }
    }
    final result = await OpenFilex.open(filePath);
    if (result.type != ResultType.done) {
      log('Error opening file: ${result.message}', isError: true);
    }
    return result.type;
  } catch (e) {
    log('Error opening file: $e', isError: true);
    return ResultType.error;
  }
}

bool isValidMasterKey(String key) {
  if (key.length != 64) return false;
  for (int i = 0; i < 64; i += 2) {
    final byteStr = key.substring(i, i + 2);
    if (int.tryParse(byteStr, radix: 16) == null) {
      return false;
    }
  }
  return true;
}

Future<bool> showInFolder(String filePath) async {
  if (kIsWeb) return false;
  final file = File(filePath);

  if (!await file.exists()) {
    return false;
  }

  try {
    if (PlatformService.isWindows) {
      await Process.run('explorer', ['/select,', filePath]);
      return true;
    } else if (PlatformService.isMacOS) {
      await Process.run('open', ['-R', filePath]);
      return true;
    } else if (PlatformService.isAndroid) {
      // On Android, try multiple methods to open the directory
      final directory = file.parent.path;

      // Method 1: Try OpenFilex first
      final result = await OpenFilex.open(directory);
      if (result.type == ResultType.done) {
        return true;
      }

      // Method 2: Fallback to url_launcher with file:// URI
      try {
        final uri = Uri.file(directory);
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) {
          return true;
        }
      } catch (e) {
        log('Error launching directory with url_launcher: $e', isError: true);
      }

      // If both methods fail, return false
      return false;
    } else if (PlatformService.isLinux) {
      // On Linux, try to open with the default file manager
      final directory = file.parent.path;
      try {
        await Process.run('xdg-open', [directory]);
        return true;
      } catch (e) {
        // Fallback to OpenFilex
        final result = await OpenFilex.open(directory);
        return result.type == ResultType.done;
      }
    } else {
      // Fallback for other platforms
      final directory = file.parent.path;
      final result = await OpenFilex.open(directory);
      return result.type == ResultType.done;
    }
  } catch (e) {
    log('Error opening folder: $e', isError: true);
    return false;
  }
}

Future<String?> getMasterKey() async {
  if (kIsWeb) return null;
  final ioService = IOServiceFactory.create();
  final configDir = await ioService.getConfigDir();
  final masterKeyPath = '$configDir/${SettingsManager.masterKeyFile}';
  if (await ioService.fileExists(masterKeyPath)) {
    final encoded = await ioService.readFile(masterKeyPath);
    return await d0(encoded);
  }
  return null;
}
