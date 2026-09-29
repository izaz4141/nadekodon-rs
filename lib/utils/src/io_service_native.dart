import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'io_service_base.dart';
import 'package:nadekodon/utils/logger.dart';
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

  /// `download_folder` as stored in this machine's own config.json, which is
  /// not the folder a remote engine downloads into.
  @override
  Future<String> getCurrentDownloadDir() async {
    final config = File('${await getConfigDir()}/config.json');
    if (!await config.exists()) return '';
    try {
      final data = jsonDecode(await config.readAsString()) as Map<String, dynamic>;
      return data['download_folder'] as String? ?? '';
    } catch (e) {
      log('Could not read download_folder from config.json: $e', isError: true);
      return '';
    }
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
    return await FilePicker.getDirectoryPath();
  }

  @override
  Future<String?> pickFile({
    List<String>? allowedExtensions,
    String? dialogTitle,
  }) async {
    final file = await FilePicker.pickFile(
      dialogTitle: dialogTitle,
      type: allowedExtensions == null ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    return file?.path;
  }

  @override
  Future<void> setPermissions(String path, String mode) async {
    if (!PlatformService.isLinux) return;
    await Process.run('chmod', [mode, path]);
  }

  @override
  String? getCookie(String name) {
    throw UnsupportedError('Theres no cookie in native app.');
  }

  @override
  Future<List<String>> processArguments() async => Platform.executableArguments;

  /// Deliberately not `print`: the zone in `main` routes that through
  /// LogService, which has no log file yet when the command line is handled.
  @override
  void writeLine(String line) => stdout.writeln(line);

  @override
  Never exit(int code) => exit(code);
}

IOService getIOService() => NativeIOService();
