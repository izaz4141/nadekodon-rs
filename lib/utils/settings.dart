import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:nadekodon/src/bindings/bindings.dart';
import 'package:nadekodon/utils/platform_service.dart';
import 'package:nadekodon/utils/logger.dart';
import 'package:nadekodon/utils/speed_scheduler.dart';
import 'package:nadekodon/utils/io_service.dart';
import 'package:nadekodon/utils/api_service.dart';

class SettingsManager {
  static late IOService _ioService;
  static late String configPath;
  static bool isFirstRun = false;
  static Map<String, dynamic> _defaults = {};

  // Your ValueNotifiers
  static final retreatToTray = ValueNotifier<bool>(true);
  static final downloadFolder = ValueNotifier<String>('');
  static final serverHost = ValueNotifier<String>('127.0.0.1');
  static final serverPort = ValueNotifier<int>(8080);
  static final serverApiKey = ValueNotifier<String>('');
  static final username = ValueNotifier<String>('');
  static final password = ValueNotifier<String>('');
  static final salt = ValueNotifier<String>('');

  // Speed Scheduler
  static final speedLimit = ValueNotifier<double>(0.0);
  static final speedMode = ValueNotifier<SpeedMode>(SpeedMode.fixed);
  static final speedSchedule = ValueNotifier<List<ScheduleRule>>([]);

  static final downloadThreads = ValueNotifier<int>(8);
  static final concurrencyLimit = ValueNotifier<int>(3);
  static final downloadTimeout = ValueNotifier<int>(30);
  static final downloadRetries = ValueNotifier<int>(5);
  static final seedingRatio = ValueNotifier<double>(1.0);
  static final seedingTime = ValueNotifier<int>(30);

  // Theme Settings
  static final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
  static final useDynamicColor = ValueNotifier<bool>(true);
  static final customColor = ValueNotifier<int>(0xFFFF4081);

  static final checkNightly = ValueNotifier<bool>(false);

  // Login Settings
  static final requireLogin = ValueNotifier<bool>(kIsWeb);
  static final isLoggedIn = ValueNotifier<bool>(false);

  static Future<void> _loadDefaults() async {
    try {
      final String response = await rootBundle.loadString(
        'assets/docs/default.json',
      );
      _defaults = json.decode(response);
    } catch (e) {
      log('Error loading default settings asset: $e');
    }
  }

  static Future<void> init() async {
    _ioService = IOServiceFactory.create();
    await _loadDefaults();

    if (kIsWeb) {
      await loadFromBackend();
      _attachAutoSave();
      SpeedScheduler.init();
      return;
    }

    final downloadsDir = await _ioService.getDownloadsDir();
    final configDir = await _ioService.getConfigDir();

    String defaultDownloadFolder = '';
    if (PlatformService.isAndroid) {
      defaultDownloadFolder = '/storage/emulated/0/Download';
    } else {
      defaultDownloadFolder = downloadsDir;
    }

    if (defaultDownloadFolder.isNotEmpty) {
      final exists = await _ioService.directoryExists(defaultDownloadFolder);
      if (!exists) {
        await _ioService.createDirectory(
          defaultDownloadFolder,
          recursive: true,
        );
      }
    }

    configPath = '$configDir/config.json';
    final configExists = await _ioService.fileExists(configPath);

    if (configExists) {
      final data = jsonDecode(await _ioService.readFile(configPath));
      await _applyFromJson(data);
      log(configPath);
    } else {
      isFirstRun = true;
      downloadFolder.value = defaultDownloadFolder;
      await applyDefaultSettings();
      regenerateApiKey();
      await _saveAll();
    }

    _attachAutoSave();
    SpeedScheduler.init();
  }

  static Future<void> _applyFromJson(Map<String, dynamic> json) async {
    retreatToTray.value =
        json['retreat_to_tray'] ?? _defaults['retreat_to_tray'] ?? true;
    downloadFolder.value = json['download_folder'] ?? '';

    // Server settings: Environment variables override saved settings
    serverHost.value =
        json['server_host'] ?? (_defaults['server_host'] ?? '127.0.0.1');
    serverPort.value =
        json['server_port'] ?? (_defaults['server_port'] ?? 8080);
    serverApiKey.value =
        json['server_api_key'] ?? (_defaults['server_api_key'] ?? '');
    if (serverApiKey.value.isEmpty) {
      regenerateApiKey();
    }
    salt.value = json['salt'] ?? '';
    if (salt.value.isEmpty) {
      await _generateSalt();
    }
    username.value = json['username'] ?? _defaults['username'] ?? 'admin';
    if (username.value.isEmpty && _defaults['username'] == "") {
      // Only fallback to admin if both are truly empty/missing
      if (username.value.isEmpty) username.value = 'admin';
    }

    final encodedPassword = json['password'] as String?;
    if (encodedPassword != null && encodedPassword.isNotEmpty) {
      password.value = await _decryptPassword(encodedPassword);
    } else {
      password.value = _defaults['password'] ?? 'admin';
      if (password.value.isEmpty) password.value = 'admin';
    }

    // Speed Scheduler
    speedLimit.value = (json['speed_limit'] ?? _defaults['speed_limit'] ?? 0.0)
        .toDouble();
    speedMode.value =
        SpeedMode.values[json['speed_mode'] ?? _defaults['speed_mode'] ?? 0];
    if (json['speed_schedule'] != null) {
      speedSchedule.value = (json['speed_schedule'] as List)
          .map((e) => ScheduleRule.fromJson(e))
          .toList();
    }

    downloadThreads.value =
        json['download_threads'] ?? _defaults['download_threads'] ?? 8;
    concurrencyLimit.value =
        json['concurrency_limit'] ?? _defaults['concurrency_limit'] ?? 3;
    downloadTimeout.value =
        json['download_timeout'] ?? _defaults['download_timeout'] ?? 30;
    downloadRetries.value =
        json['download_retries'] ?? _defaults['download_retries'] ?? 5;

    seedingRatio.value =
        (json['seeding_ratio'] ?? _defaults['seeding_ratio'] ?? 1.0).toDouble();
    seedingTime.value = json['seeding_time'] ?? _defaults['seeding_time'] ?? 30;

    // Theme Settings
    if (json['theme_mode'] != null) {
      themeMode.value = ThemeMode.values[json['theme_mode']];
    } else if (_defaults['theme_mode'] != null) {
      themeMode.value = ThemeMode.values[_defaults['theme_mode']];
    }
    useDynamicColor.value =
        json['use_dynamic_color'] ?? _defaults['use_dynamic_color'] ?? true;
    customColor.value =
        json['custom_color'] ?? _defaults['custom_color'] ?? 0xFFFF4081;
    checkNightly.value =
        json['check_nightly'] ?? _defaults['check_nightly'] ?? false;
    requireLogin.value = json['require_login'] ?? (kIsWeb ? true : false);
  }

  static Future<Map<String, dynamic>> _toJson() async => {
    'retreat_to_tray': retreatToTray.value,
    'download_folder': downloadFolder.value,
    'server_host': serverHost.value,
    'server_port': serverPort.value,
    'server_api_key': serverApiKey.value,
    'salt': salt.value,
    'username': username.value,
    'password': await _encryptPassword(password.value),
    'speed_limit': speedLimit.value,
    'speed_mode': speedMode.value.index,
    'speed_schedule': speedSchedule.value.map((e) => e.toJson()).toList(),
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
    'require_login': requireLogin.value,
  };

  static Future<void> _saveAll() async {
    if (kIsWeb) {
      await _saveToBackend();
      return;
    }
    final jsonMap = await _toJson();
    await _ioService.writeFile(
      configPath,
      const JsonEncoder.withIndent('  ').convert(jsonMap),
    );
  }

  static Future<void> _saveChanged(String key, dynamic value) async {
    if (!kIsWeb) {
      _sendSettings(key, value);
    } else {
      await _saveToBackend();
      return;
    }

    Map<String, dynamic> data = {};

    final configExists = await _ioService.fileExists(configPath);
    if (configExists) {
      try {
        data = jsonDecode(await _ioService.readFile(configPath));
      } catch (e) {
        log("Error reading config file: $e");
        data = await _toJson();
      }
    }

    if (key == 'password') {
      data[key] = await _encryptPassword(value);
    } else {
      data[key] = value;
    }
    await _ioService.writeFile(
      configPath,
      const JsonEncoder.withIndent('  ').convert(data),
    );
  }

  static void _attachAutoSave() {
    retreatToTray.addListener(
      () => _saveChanged('retreat_to_tray', retreatToTray.value),
    );
    downloadFolder.addListener(
      () => _saveChanged('download_folder', downloadFolder.value),
    );
    serverHost.addListener(() => _saveChanged('server_host', serverHost.value));
    serverPort.addListener(() => _saveChanged('server_port', serverPort.value));
    serverApiKey.addListener(
      () => _saveChanged('server_api_key', serverApiKey.value),
    );
    username.addListener(() => _saveChanged('username', username.value));
    password.addListener(() => _saveChanged('password', password.value));
    salt.addListener(() => _saveChanged('salt', salt.value));
    speedLimit.addListener(() => _saveChanged('speed_limit', speedLimit.value));
    speedMode.addListener(
      () => _saveChanged('speed_mode', speedMode.value.index),
    );
    speedSchedule.addListener(
      () => _saveChanged(
        'speed_schedule',
        speedSchedule.value.map((e) => e.toJson()).toList(),
      ),
    );
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
    requireLogin.addListener(
      () => _saveChanged('require_login', requireLogin.value),
    );
  }

  static void _sendSettings(String key, dynamic value) {
    switch (key) {
      case 'download_folder':
        UpdateSettings(downloadDir: value).sendSignalToRust();
        break;
      case 'speed_limit':
        if (speedMode.value == SpeedMode.fixed) {
          sendSpeedLimit(value);
        }
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
    if (kIsWeb) return;
    UpdateSettings(
      downloadDir: downloadFolder.value,
      speedLimit: Uint64.fromBigInt(
        BigInt.from((SpeedScheduler.currentSpeed.value * 1024 * 1024).round()),
      ),
      downloadThreads: downloadThreads.value,
      concurrencyLimit: concurrencyLimit.value,
      downloadRetries: downloadRetries.value,
      downloadTimeout: Uint64.fromBigInt(BigInt.from(downloadTimeout.value)),
      seedingRatio: seedingRatio.value,
      seedingTime: Uint64.fromBigInt(BigInt.from(seedingTime.value)),
    ).sendSignalToRust();
  }

  static void sendSpeedLimit(double value) {
    if (kIsWeb) return;
    UpdateSettings(
      speedLimit: Uint64.fromBigInt(BigInt.from((value * 1024 * 1024).round())),
    ).sendSignalToRust();
  }

  static Future<void> applyDefaultSettings() async {
    retreatToTray.value = _defaults['retreat_to_tray'] ?? true;
    // downloadFolder is usually not reset to default from asset as it's environment dependent
    username.value = _defaults['username'] ?? 'admin';
    if (username.value.isEmpty) username.value = 'admin';
    password.value = _defaults['password'] ?? 'admin';
    if (password.value.isEmpty) password.value = 'admin';

    if (salt.value.isEmpty) {
      await _generateSalt();
    }
    serverPort.value = _defaults['server_port'] ?? 8080;
    speedLimit.value = (_defaults['speed_limit'] ?? 0.0).toDouble();
    downloadThreads.value = _defaults['download_threads'] ?? 8;
    concurrencyLimit.value = _defaults['concurrency_limit'] ?? 3;
    downloadTimeout.value = _defaults['download_timeout'] ?? 30;
    downloadRetries.value = _defaults['download_retries'] ?? 5;
    seedingRatio.value = (_defaults['seeding_ratio'] ?? 1.0).toDouble();
    seedingTime.value = _defaults['seeding_time'] ?? 30;

    if (_defaults['theme_mode'] != null) {
      themeMode.value = ThemeMode.values[_defaults['theme_mode']];
    }
    useDynamicColor.value = _defaults['use_dynamic_color'] ?? true;
    customColor.value = _defaults['custom_color'] ?? 0xFFFF4081;
    checkNightly.value = _defaults['check_nightly'] ?? false;

    speedMode.value = SpeedMode.values[_defaults['speed_mode'] ?? 0];
    speedSchedule.value = [];
  }

  static Future<String> getDatabasePath() async {
    return _ioService.getDatabasePath();
  }

  static Future<String> getTorrentPersistencePath() async {
    return _ioService.getTorrentPersistencePath();
  }

  static Future<void> regenerateApiKey() async {
    if (kIsWeb) {
      await APIService.regenerateApiKey();
      return;
    }
    RequestNewApiKey().sendSignalToRust();
    final signal = await NewApiKey.rustSignalStream.first;
    serverApiKey.value = signal.message.key;
  }

  static Future<void> restartServer() async {
    if (kIsWeb) {
      await APIService.restartServer();
      return;
    }
    StartServer(
      port: serverPort.value,
      apiKey: serverApiKey.value,
      username: username.value,
      password: password.value,
    ).sendSignalToRust();
  }

  static Future<void> _generateSalt() async {
    if (kIsWeb) {
      final newSalt = await APIService.generateSalt();
      if (newSalt != null) salt.value = newSalt;
      return;
    } else {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final stream = SaltOutput.rustSignalStream.where(
        (signal) => signal.message.id == id,
      );
      GenerateSalt(id: id).sendSignalToRust();
      final signal = await stream.first;
      salt.value = signal.message.salt;
    }
  }

  static Future<String> _encryptPassword(String plainText) async {
    if (plainText.isEmpty) return '';
    try {
      if (kIsWeb) {
        final encrypted = await APIService.encryptPassword(
          plainText,
          salt.value,
        );
        if (encrypted != null) return encrypted;
      } else {
        final id = DateTime.now().microsecondsSinceEpoch.toString();
        final stream = EncryptionOutput.rustSignalStream.where(
          (signal) => signal.message.id == id,
        );
        EncryptPassword(
          id: id,
          plainText: plainText,
          salt: salt.value,
        ).sendSignalToRust();
        final signal = await stream.first;
        if (signal.message.encryptedText != null) {
          return signal.message.encryptedText!;
        }
      }

      // Fallback: If server is not available, we can't encrypt.
      // Returning plain text would be wrong if it's expected to be JSON.
      // But for now, let's return base64 of plain text as a last resort.
      return base64.encode(utf8.encode(plainText));
    } catch (e) {
      log("Encryption error: $e");
      return base64.encode(utf8.encode(plainText));
    }
  }

  static Future<String> _decryptPassword(String stored) async {
    if (stored.isEmpty) return '';
    try {
      if (kIsWeb) {
        final decrypted = await APIService.decryptPassword(stored, salt.value);
        if (decrypted != null) return decrypted;
      } else {
        final id = DateTime.now().microsecondsSinceEpoch.toString();
        final stream = DecryptionOutput.rustSignalStream.where(
          (signal) => signal.message.id == id,
        );
        DecryptPassword(
          id: id,
          encryptedText: stored,
          salt: salt.value,
        ).sendSignalToRust();
        final signal = await stream.first;
        if (signal.message.plainText != null) {
          return signal.message.plainText!;
        }
      }
    } catch (e) {
      log("Decryption error: $e");
    }

    // Fallback for migration or plain Base64
    try {
      return utf8.decode(base64.decode(stored));
    } catch (_) {
      return stored;
    }
  }

  static Future<void> loadFromBackend() async {
    final data = await APIService.getSettings();
    if (data != null) {
      await _applyFromJson(data);
    } else {
      log('Failed to load settings from backend');
    }
  }

  static Future<void> _saveToBackend() async {
    final jsonMap = await _toJson();
    final success = await APIService.saveSettings(jsonMap);
    if (!success) {
      log('Failed to save settings to backend');
    }
  }
}
