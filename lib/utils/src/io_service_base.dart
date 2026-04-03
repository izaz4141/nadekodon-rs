import 'dart:async';
import 'package:flutter/foundation.dart';

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
  Future<String?> getDirectoryPath();
  Future<void> setPermissions(String path, String mode);
}
