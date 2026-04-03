import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'io_service_base.dart';
import 'package:nadekodon/utils/platform_service.dart';

class NativeIOService implements IOService {
  final Map<String, Lock> _fileLocks = {};

  Lock _getLock(String path) =>
      _fileLocks.putIfAbsent(path, () => Lock(reentrant: true));

  @override
  Future<String> getConfigDir() async {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }

  @override
  Future<String> getDownloadsDir() async {
    final downloads = await getDownloadsDirectory();
    return downloads?.path ?? '';
  }

  @override
  Future<String> getDatabasePath() async {
    final configDir = await getConfigDir();
    return '$configDir/nadekodon.db';
  }

  @override
  Future<String> getTorrentPersistencePath() async {
    final configDir = await getConfigDir();
    return '$configDir/torrent_data';
  }

  @override
  Future<bool> fileExists(String path) async {
    return File(path).exists();
  }

  @override
  Future<String> readFile(String path) async {
    return await _getLock(path).synchronized(() async {
      return File(path).readAsString();
    });
  }

  @override
  Future<void> writeFile(String path, String content) async {
    await File(path).parent.create(recursive: true);
    await _getLock(path).synchronized(() async {
      await File(path).writeAsString(content);
    });
  }

  @override
  Future<void> createDirectory(String path, {bool recursive = false}) async {
    final dir = Directory(path);
    await dir.create(recursive: recursive);
  }

  @override
  Future<bool> directoryExists(String path) async {
    return Directory(path).exists();
  }

  @override
  Future<Uint8List> readFileBytes(String path) async {
    return await _getLock(path).synchronized(() async {
      return File(path).readAsBytes();
    });
  }

  @override
  Future<void> writeFileBytes(String path, Uint8List bytes) async {
    await File(path).parent.create(recursive: true);
    await _getLock(path).synchronized(() async {
      await File(path).writeAsBytes(bytes);
    });
  }

  @override
  Future<String?> getDirectoryPath() async {
    return await FilePicker.platform.getDirectoryPath();
  }

  @override
  Future<void> setPermissions(String path, String mode) async {
    if (!PlatformService.isLinux) return;
    await Process.run('chmod', [mode, path]);
  }
}

IOService getIOService() => NativeIOService();
