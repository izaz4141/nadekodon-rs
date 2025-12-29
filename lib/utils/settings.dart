import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:nadekodon/src/bindings/bindings.dart';
import 'package:nadekodon/utils/defaults.dart';
import 'package:nadekodon/utils/logger.dart';

class SettingsManager {
  static late File _file;
  static late String configPath;
  static late Directory? downloadsDir;
  static late Directory? configDir;
  static bool isFirstRun = false;

  // Your ValueNotifiers
  static final retreatToTray = ValueNotifier<bool>(
    DefaultSettings.retreatToTray,
  );
  static final downloadFolder = ValueNotifier<String>('');
  static final serverPort = ValueNotifier<int>(DefaultSettings.serverPort);
  static final serverApiKey = ValueNotifier<String>('');
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
  static final seedingRatio = ValueNotifier<double>(
    DefaultSettings.seedingRatio,
  );
  static final seedingTime = ValueNotifier<int>(DefaultSettings.seedingTime);

  // Theme Settings
  static final themeMode = ValueNotifier<ThemeMode>(DefaultSettings.themeMode);
  static final useDynamicColor = ValueNotifier<bool>(
    DefaultSettings.useDynamicColor,
  );
  static final customColor = ValueNotifier<int>(
    DefaultSettings.customColor,
  ); // PinkAccent default

  static final checkNightly = ValueNotifier<bool>(DefaultSettings.checkNightly);

  /// Init config system (call at app startup)
  static Future<void> init() async {
    // On Android, use the public Downloads directory via external storage
    if (Platform.isAndroid) {
      downloadsDir = Directory('/storage/emulated/0/Download');
      DefaultSettings.downloadFolder = downloadsDir!.path;
    } else {
      downloadsDir = await getDownloadsDirectory();
      DefaultSettings.downloadFolder = downloadsDir?.path ?? '';
    }
    configDir = await getApplicationSupportDirectory();
    configPath = '${configDir!.path}/config.json';
    _file = File(configPath);

    if (await _file.exists()) {
      final data = jsonDecode(await _file.readAsString());
      _applyFromJson(data);
      log(configPath);
    } else {
      isFirstRun = true;
      applyDefaultSettings();
      regenerateApiKey();
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
    serverApiKey.value = json['server_api_key'] ?? '';
    if (serverApiKey.value.isEmpty) {
      regenerateApiKey();
    }
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

    seedingRatio.value = json['seeding_ratio'] ?? DefaultSettings.seedingRatio;
    seedingTime.value = json['seeding_time'] ?? DefaultSettings.seedingTime;

    // Theme Settings
    if (json['theme_mode'] != null) {
      themeMode.value = ThemeMode.values[json['theme_mode']];
    }
    useDynamicColor.value = json['use_dynamic_color'] ?? true;
    customColor.value = json['custom_color'] ?? 0xFFFF4081;
    checkNightly.value = json['check_nightly'] ?? DefaultSettings.checkNightly;
  }

  static Map<String, dynamic> _toJson() => {
    'retreat_to_tray': retreatToTray.value,
    'download_folder': downloadFolder.value,
    'server_port': serverPort.value,
    'server_api_key': serverApiKey.value,
    'speed_limit': speedLimit.value,
    'download_threads': downloadThreads.value,
    'concurrency_limit': concurrencyLimit.value,
    'download_timeout': downloadTimeout.value,
    'download_retries': downloadRetries.value,
    'seeding_ratio': seedingRatio.value,
    'seeding_time': seedingTime.value,
    'theme_mode': themeMode.value.index,
    'use_dynamic_color': useDynamicColor.value,
    'custom_color': customColor.value,
    'check_nightly': checkNightly.value,
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
    serverApiKey.addListener(
      () => _saveChanged('server_api_key', serverApiKey.value),
    );
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

    seedingRatio.addListener(
      () => _saveChanged('seeding_ratio', seedingRatio.value),
    );
    seedingTime.addListener(
      () => _saveChanged('seeding_time', seedingTime.value),
    );

    themeMode.addListener(
      () => _saveChanged('theme_mode', themeMode.value.index),
    );
    useDynamicColor.addListener(
      () => _saveChanged('use_dynamic_color', useDynamicColor.value),
    );
    customColor.addListener(
      () => _saveChanged('custom_color', customColor.value),
    );
    checkNightly.addListener(
      () => _saveChanged('check_nightly', checkNightly.value),
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
      case 'seeding_ratio':
        UpdateSettings(seedingRatio: value).sendSignalToRust();
        break;
      case 'seeding_time':
        UpdateSettings(
          seedingTime: Uint64.fromBigInt(BigInt.from(value)),
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
      seedingRatio: seedingRatio.value,
      seedingTime: Uint64.fromBigInt(BigInt.from(seedingTime.value)),
    ).sendSignalToRust();
  }

  static void applyDefaultSettings() {
    retreatToTray.value = DefaultSettings.retreatToTray;
    downloadFolder.value = DefaultSettings.downloadFolder;
    serverPort.value = DefaultSettings.serverPort;
    speedLimit.value = DefaultSettings.speedLimit;
    downloadThreads.value = DefaultSettings.downloadThreads;
    concurrencyLimit.value = DefaultSettings.concurrencyLimit;
    downloadTimeout.value = DefaultSettings.downloadTimeout;
    downloadRetries.value = DefaultSettings.downloadRetries;
    seedingRatio.value = DefaultSettings.seedingRatio;
    seedingTime.value = DefaultSettings.seedingTime;

    themeMode.value = DefaultSettings.themeMode;
    useDynamicColor.value = DefaultSettings.useDynamicColor;
    customColor.value = DefaultSettings.customColor;
    checkNightly.value = DefaultSettings.checkNightly;
  }

  static Future<String> getDatabasePath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/nadekodon.db';
  }

  static Future<String> getTorrentPersistencePath() async {
    final dir = await getApplicationSupportDirectory();
    return '${dir.path}/torrent_data';
  }

  static Future<void> regenerateApiKey() async {
    RequestNewApiKey().sendSignalToRust();
    final signal = await NewApiKey.rustSignalStream.first;
    serverApiKey.value = signal.message.key;
  }

  static void restartServer() {
    StartServer(
      port: serverPort.value,
      apiKey: serverApiKey.value,
    ).sendSignalToRust();
  }
}
