import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as html;
import 'io_service_base.dart';

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

  @override
  Future<String?> getDirectoryPath() async {
    throw UnsupportedError('Directory picker is not supported in WASM.');
  }

  @override
  Future<void> setPermissions(String path, String mode) async {}

  @override
  String? getCookie(String name) {
    final String rawCookies = html.window.document.cookie;
    if (rawCookies.isEmpty) return null;

    final List<String> cookies = rawCookies.split(';');

    for (final cookie in cookies) {
      final List<String> pair = cookie.split('=');
      if (pair.length == 2 && pair[0].trim() == name) {
        return pair[1].trim();
      }
    }
    return null;
  }
}

IOService getIOService() => WasmIOService();
