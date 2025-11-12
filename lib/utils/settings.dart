import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:nadekodon/src/bindings/bindings.dart';
import 'package:nadekodon/utils/defaults.dart';
import 'package:nadekodon/utils/logger.dart';

class SettingsManager {
  static late File _file;
  static late String configPath;
  static late Directory? downloadsDir;
  static late Directory? configDir;

  // Your ValueNotifiers
  static final retreatToTray = ValueNotifier<bool>(
    DefaultSettings.retreatToTray,
  );
  static final downloadFolder = ValueNotifier<String>('');
  static final serverPort = ValueNotifier<int>(DefaultSettings.serverPort);
  static final speedLimit = ValueNotifier<double>(DefaultSettings.speedLimit);
  static final downloadThreads = ValueNotifier<int>(
    DefaultSettings.downloadThreads,
  );
  static final concurrencyLimit = ValueNotifier<int>(
    DefaultSettings.concurrencyLimit,
  );
  static final downloadTimeout = ValueNotifier<int>(
    DefaultSettings.downloadTimeout,
  );
  static final downloadRetries = ValueNotifier<int>(
    DefaultSettings.downloadRetries,
  );

  /// Init config system (call at app startup)
  static Future<void> init() async {
    downloadsDir = await getDownloadsDirectory();
    DefaultSettings.downloadFolder = downloadsDir?.path ?? '';
    configDir = await getApplicationSupportDirectory();
    configPath = '${configDir!.path}/config.json';
    _file = File(configPath);

    if (await _file.exists()) {
      final data = jsonDecode(await _file.readAsString());
      _applyFromJson(data);
      log(configPath);
    } else {
      log("Initial Config");
      downloadFolder.value = '';
      await _saveAll();
    }

    _attachAutoSave();
  }

  static void _applyFromJson(Map<String, dynamic> json) {
    retreatToTray.value =
        json['retreat_to_tray'] ?? DefaultSettings.retreatToTray;
    downloadFolder.value =
        json['download_folder'] ?? DefaultSettings.downloadFolder;
    serverPort.value = json['server_port'] ?? DefaultSettings.serverPort;
    speedLimit.value = (json['speed_limit'] ?? DefaultSettings.speedLimit)
        .toDouble();
    downloadThreads.value =
        json['download_threads'] ?? DefaultSettings.downloadThreads;
    concurrencyLimit.value =
        json['concurrency_limit'] ?? DefaultSettings.concurrencyLimit;
    downloadTimeout.value =
        json['download_timeout'] ?? DefaultSettings.downloadTimeout;
    downloadRetries.value =
        json['download_retries'] ?? DefaultSettings.downloadRetries;
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

    await _file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }

  static void _attachAutoSave() {
    retreatToTray.addListener(
      () => _saveChanged('retreat_to_tray', retreatToTray.value),
    );
    downloadFolder.addListener(
      () => _saveChanged('download_folder', downloadFolder.value),
    );
    serverPort.addListener(() => _saveChanged('server_port', serverPort.value));
    speedLimit.addListener(() => _saveChanged('speed_limit', speedLimit.value));
    downloadThreads.addListener(
      () => _saveChanged('download_threads', downloadThreads.value),
    );
    concurrencyLimit.addListener(
      () => _saveChanged('concurrency_limit', concurrencyLimit.value),
    );
    downloadTimeout.addListener(
      () => _saveChanged('download_timeout', downloadTimeout.value),
    );
    downloadRetries.addListener(
      () => _saveChanged('download_retries', downloadRetries.value),
    );
  }

  static void _sendSettings(String key, dynamic value) {
    switch (key) {
      case 'speed_limit':
        UpdateSettings(
          speedLimit: Uint64.fromBigInt(
            BigInt.from((value * 1024 * 1024).round()),
          ),
        ).sendSignalToRust();
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
        UpdateSettings(
          downloadTimeout: Uint64.fromBigInt(BigInt.from(value)),
        ).sendSignalToRust();
        break;
    }
  }

  static Future<void> sendAllSettings() async {
    UpdateSettings(
      speedLimit: Uint64.fromBigInt(
        BigInt.from((speedLimit.value * 1024 * 1024).round()),
      ),
      downloadThreads: downloadThreads.value,
      concurrencyLimit: concurrencyLimit.value,
      downloadRetries: downloadRetries.value,
      downloadTimeout: Uint64.fromBigInt(BigInt.from(downloadTimeout.value)),
    ).sendSignalToRust();
  }
}
