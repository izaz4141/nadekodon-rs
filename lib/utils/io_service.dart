import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';
import 'package:path_provider/path_provider.dart';

abstract class IOService {
  Future<String> getConfigDir();
  Future<String> getDownloadsDir();
  Future<String> getDatabasePath();
  Future<String> getTorrentPersistencePath();
  Future<bool> fileExists(String path);
  Future<String> readFile(String path);
  Future<void> writeFile(String path, String content);
  Future<void> createDirectory(String path, {bool recursive = false});
  Future<bool> directoryExists(String path);
  Future<Uint8List> readFileBytes(String path);
  Future<void> writeFileBytes(String path, Uint8List bytes);
}

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
}

class WasmIOService implements IOService {
  @override
  Future<String> getConfigDir() async {
    throw UnsupportedError(
      'Filesystem access is not supported in WASM. Use APIService for settings.',
    );
  }

  @override
  Future<String> getDownloadsDir() async {
    throw UnsupportedError(
      'Filesystem access is not supported in WASM. Use APIService for settings.',
    );
  }

  @override
  Future<String> getDatabasePath() async {
    throw UnsupportedError('Filesystem access is not supported in WASM.');
  }

  @override
  Future<String> getTorrentPersistencePath() async {
    throw UnsupportedError('Filesystem access is not supported in WASM.');
  }

  @override
  Future<bool> fileExists(String path) async {
    throw UnsupportedError('Filesystem access is not supported in WASM.');
  }

  @override
  Future<String> readFile(String path) async {
    throw UnsupportedError(
      'Filesystem access is not supported in WASM. Use APIService for settings.',
    );
  }

  @override
  Future<void> writeFile(String path, String content) async {
    throw UnsupportedError(
      'Filesystem access is not supported in WASM. Use APIService for settings.',
    );
  }

  @override
  Future<void> createDirectory(String path, {bool recursive = false}) async {
    throw UnsupportedError('Filesystem access is not supported in WASM.');
  }

  @override
  Future<bool> directoryExists(String path) async {
    throw UnsupportedError('Filesystem access is not supported in WASM.');
  }

  @override
  Future<Uint8List> readFileBytes(String path) async {
    throw UnsupportedError('Filesystem access is not supported in WASM.');
  }

  @override
  Future<void> writeFileBytes(String path, Uint8List bytes) async {
    throw UnsupportedError('Filesystem access is not supported in WASM.');
  }
}

class IOServiceFactory {
  static IOService create() {
    if (kIsWeb) {
      return WasmIOService();
    }
    return NativeIOService();
  }
}
