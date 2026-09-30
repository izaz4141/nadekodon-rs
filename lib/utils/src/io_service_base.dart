import 'dart:async';
import 'package:flutter/foundation.dart';

abstract class IOService {
  Future<String> getConfigDir();
  Future<String> getDownloadsDir();
  Future<String> getCurrentDownloadDir();
  Future<String> getDatabasePath();
  Future<String> getTorrentPersistencePath();
  Future<bool> fileExists(String path);
  Future<String> readFile(String path);
  Future<void> writeFile(String path, String content, {bool flush = false});
  Future<void> deleteFile(String path);
  Future<void> createDirectory(String path, {bool recursive = false});
  Future<bool> directoryExists(String path);
  Future<Uint8List> readFileBytes(String path);
  Future<void> writeFileBytes(String path, Uint8List bytes);
  Future<String?> getDirectoryPath();
  Future<String?> pickFile({
    List<String>? allowedExtensions,
    String? dialogTitle,
  });
  Future<void> setPermissions(String path, String mode);
  String? getCookie(String name);
  void writeLine(String line);
  Never exit(int code);
  Future<LocalChannel> connectLocalChannel(int port);
  Future<LocalServer> bindLocalChannel();
}

/// A one-shot loopback connection that hands a message to whoever is listening.
abstract class LocalChannel {
  Future<void> send(String message);
}

/// The loopback listener held by the main instance.
abstract class LocalServer {
  /// The port [bindLocalChannel] was actually assigned, which matters because
  /// the bind itself uses an ephemeral port.
  int get port;

  /// [onMessage] fires once per complete message, after the sender has closed.
  void onMessage(void Function(String message) onMessage);

  Future<void> close();
}
