import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:rinf/rinf.dart';
import 'package:nadekodon/src/bindings/bindings.dart';
import 'package:nadekodon/utils/helper.dart';

class SettingsManager {
  static late File _file;
  static late String configPath;


  // Your ValueNotifiers
  static final retreatToTray = ValueNotifier<bool>(true);
  static final downloadFolder = ValueNotifier<String>('');
  static final serverPort = ValueNotifier<int>(8080);
  static final speedLimit = ValueNotifier<double>(0.0);
  static final downloadThreads = ValueNotifier<int>(8);
  static final concurrencyLimit = ValueNotifier<int>(3);
  static final downloadTimeout = ValueNotifier<int>(30);
  static final downloadRetries = ValueNotifier<int>(5);

  /// Init config system (call at app startup)
  static Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    configPath = '${dir.path}/config.json';
    _file = File(configPath);

    if (await _file.exists()) {
      final data = jsonDecode(await _file.readAsString());
      _applyFromJson(data);
      debugPrint(configPath);
    } else {
      debugPrint("Initial Config");
      await _saveAll();
    }

    _attachAutoSave();
  }

  static void _applyFromJson(Map<String, dynamic> json) {
    retreatToTray.value = json['retreat_to_tray'] ?? true;
    downloadFolder.value = json['download_folder'] ?? '';
    serverPort.value = json['server_port'] ?? 8080;
    speedLimit.value = (json['speed_limit'] ?? 2.0).toDouble();
    downloadThreads.value = json['download_threads'] ?? 8;
    concurrencyLimit.value = json['concurrency_limit'] ?? 3;
    downloadTimeout.value = json['download_timeout'] ?? 30;
    downloadRetries.value = json['download_retries'] ?? 5;
  }

  static Map<String, dynamic> _toJson() => {
        'retreat_to_tray': retreatToTray.value,
        'download_folder': downloadFolder.value,
        'server_port': serverPort.value,
        'speed_limit': speedLimit.value,
        'download_threads': downloadThreads.value,
        'concurrency_limit': concurrencyLimit.value,
        'download_timeout': downloadTimeout.value,
        'download_retries': downloadRetries.value,
      };

  /// Save entire config (initial only)
  static Future<void> _saveAll() async {
    await _file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_toJson()),
    );
  }

  /// Save only one changed key/value
  static Future<void> _saveChanged(String key, dynamic value) async {
    Map<String, dynamic> data = {};

    if (await _file.exists()) {
      data = jsonDecode(await _file.readAsString());
    }

    data[key] = value;
    _sendSettings(key, value);

    await _file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
    );
  }

  static void _attachAutoSave() {
    retreatToTray.addListener(() =>
        _saveChanged('retreat_to_tray', retreatToTray.value));
    downloadFolder.addListener(() =>
        _saveChanged('download_folder', downloadFolder.value));
    serverPort.addListener(
        () => _saveChanged('server_port', serverPort.value));
    speedLimit.addListener(
        () => _saveChanged('speed_limit', speedLimit.value));
    downloadThreads.addListener(
        () => _saveChanged('download_threads', downloadThreads.value));
    concurrencyLimit.addListener(
        () => _saveChanged('concurrency_limit', concurrencyLimit.value));
    downloadTimeout.addListener(
        () => _saveChanged('download_timeout', downloadTimeout.value));
    downloadRetries.addListener(
        () => _saveChanged('download_retries', downloadRetries.value));
  }

  static void _sendSettings(String key, dynamic value) {
    switch (key) {
      case 'speed_limit':
        UpdateSettings(speedLimit: Uint64.fromBigInt(BigInt.from((value * 1024*1024).round()))).sendSignalToRust();
        break;
      case 'download_threads':
        UpdateSettings(downloadThreads: value).sendSignalToRust();
        break;
      case 'concurrency_limit':
        UpdateSettings(concurrencyLimit: value).sendSignalToRust();
        break;
      case 'download_retries':
        UpdateSettings(downloadRetries: value).sendSignalToRust();
        break;
      case 'download_timeout':
        UpdateSettings(downloadTimeout: Uint64.fromBigInt(BigInt.from(value))).sendSignalToRust();
        break;
    }
  }

  static Future<void> sendAllSettings() async {
    UpdateSettings(
      speedLimit: Uint64.fromBigInt(BigInt.from((speedLimit.value * 1024*1024).round())),
      downloadThreads: downloadThreads.value,
      concurrencyLimit: concurrencyLimit.value,
      downloadRetries: downloadRetries.value,
      downloadTimeout: Uint64.fromBigInt(BigInt.from(downloadTimeout.value))
    ).sendSignalToRust();
  }
}
