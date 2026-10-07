import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:nadekodon/utils/bridge_service.dart';
import 'package:nadekodon/utils/logger.dart';
import 'package:nadekodon/utils/platform_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';

import 'io_service_base.dart';

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

  /// Local `download_folder`; not the folder a remote engine downloads into.
  @override
  Future<String> getCurrentDownloadDir() async {
    final result = await BridgeService.readLocalConfig(
      '${await getConfigDir()}/config.json',
    );
    return result.settings?['download_folder'] as String? ?? '';
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
  Future<void> writeFile(
    String path,
    String content, {
    bool flush = false,
  }) async {
    await File(path).parent.create(recursive: true);
    await _getLock(path).synchronized(() async {
      await File(path).writeAsString(content, flush: flush);
    });
  }

  @override
  Future<void> deleteFile(String path) async {
    await _getLock(path).synchronized(() async {
      await File(path).delete();
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

  /// Deliberately not `print`: the zone in `main` routes that through
  /// LogService, which has no log file yet when the command line is handled.
  @override
  void writeLine(String line) => stdout.writeln(line);

  @override
  Never exit(int code) => io.exit(code);

  @override
  Future<LocalChannel> connectLocalChannel(int port) async {
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
    return _NativeLocalChannel(socket);
  }

  @override
  Future<LocalServer> bindLocalChannel() async {
    // Port 0 asks the OS for an ephemeral port, reported by `LocalServer.port`.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    return _NativeLocalServer(server);
  }
}

class _NativeLocalChannel implements LocalChannel {
  _NativeLocalChannel(this._socket);

  final Socket _socket;

  @override
  Future<void> send(String message) async {
    _socket.write(message);
    await _socket.flush();
    await _socket.close();
  }
}

class _NativeLocalServer implements LocalServer {
  _NativeLocalServer(this._server);

  final ServerSocket _server;

  @override
  int get port => _server.port;

  @override
  void onMessage(void Function(String message) onMessage) {
    _server.listen((socket) {
      // A read is not a message: a target can straddle packets, so the chunks
      // are collected until the sender closes.
      final chunks = <int>[];
      socket.listen(
        chunks.addAll,
        onDone: () => onMessage(utf8.decode(chunks)),
        onError: (Object e) => log('Local channel socket failed: $e'),
      );
    });
  }

  @override
  Future<void> close() => _server.close();
}

IOService getIOService() => NativeIOService();
