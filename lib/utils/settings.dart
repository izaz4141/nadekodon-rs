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
import 'package:nadekodon/models/account.dart';

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

  static final accounts = ValueNotifier<List<Account>>([]);
  static final Map<ValueNotifier, VoidCallback> _autoSaveListeners = {};

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
      log('Error loading default settings asset: $e', isError: true);
    }
  }

  static Future<void> init() async {
    _ioService = IOServiceFactory.create();
    await _loadDefaults();

    if (kIsWeb) {
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
      final Map<String, dynamic> data = jsonDecode(
        await _ioService.readFile(configPath),
      );
      serverHost.value =
          data['server_host'] ?? (_defaults['server_host'] ?? '127.0.0.1');
      serverPort.value =
          data['server_port'] ?? (_defaults['server_port'] ?? 8080);
      await _applyFromJson(data);
      log(configPath);
    } else {
      isFirstRun = true;
      downloadFolder.value = defaultDownloadFolder;
      await applyDefaultSettings();
      await regenerateApiKey();
      await _saveAll();
    }

    attachAutoSave();
    SpeedScheduler.init();
  }

  static Future<void> _applyFromJson(Map<String, dynamic> json) async {
    retreatToTray.value =
        json['retreat_to_tray'] ?? _defaults['retreat_to_tray'] ?? true;
    downloadFolder.value = json['download_folder'] ?? '';

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
      password.value = encodedPassword;
    } else {
      password.value = _defaults['password'] ?? await _hashPassword('admin');
      if (password.value.isEmpty) password.value = await _hashPassword('admin');
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

    if (json['accounts'] != null) {
      accounts.value = (json['accounts'] as List)
          .map((e) => Account.fromJson(e))
          .toList();
    }
  }

  static Future<Map<String, dynamic>> _toJson() async => {
    'retreat_to_tray': retreatToTray.value,
    'download_folder': downloadFolder.value,
    'server_host': serverHost.value,
    'server_port': serverPort.value,
    'server_api_key': serverApiKey.value,
    'salt': salt.value,
    'username': username.value,
    'password': await _hashPassword(password.value),
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
    'accounts': accounts.value.map((e) => e.toJson()).toList(),
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
    if (PlatformService().isRemote) {
      if (key != 'accounts') {
        await _saveToBackend();
      }
    } else {
      _sendSettings(key, value);
    }

    Map<String, dynamic> data = {};

    final configExists = await _ioService.fileExists(configPath);
    if (configExists) {
      try {
        data = jsonDecode(await _ioService.readFile(configPath));
      } catch (e) {
        log("Error reading config file: $e", isError: true);
        data = await _toJson();
      }
    }

    if (key == 'password') {
      data[key] = await _hashPassword(value);
    } else {
      data[key] = value;
    }
    await _ioService.writeFile(
      configPath,
      const JsonEncoder.withIndent('  ').convert(data),
    );
  }

  static void attachAutoSave() {
    detachAutoSave();

    void add(ValueNotifier n, String key, [dynamic Function()? getValue]) {
      void listener() =>
          _saveChanged(key, getValue != null ? getValue() : n.value);
      n.addListener(listener);
      _autoSaveListeners[n] = listener;
    }

    add(retreatToTray, 'retreat_to_tray');
    add(downloadFolder, 'download_folder');
    add(serverHost, 'server_host');
    add(serverPort, 'server_port');
    add(serverApiKey, 'server_api_key');
    add(username, 'username');
    add(password, 'password');
    add(salt, 'salt');
    add(speedLimit, 'speed_limit');
    add(speedMode, 'speed_mode', () => speedMode.value.index);
    add(
      speedSchedule,
      'speed_schedule',
      () => speedSchedule.value.map((e) => e.toJson()).toList(),
    );
    add(downloadThreads, 'download_threads');
    add(concurrencyLimit, 'concurrency_limit');
    add(downloadTimeout, 'download_timeout');
    add(downloadRetries, 'download_retries');
    add(seedingRatio, 'seeding_ratio');
    add(seedingTime, 'seeding_time');
    add(themeMode, 'theme_mode', () => themeMode.value.index);
    add(useDynamicColor, 'use_dynamic_color');
    add(customColor, 'custom_color');
    add(checkNightly, 'check_nightly');
    add(requireLogin, 'require_login');
    add(
      accounts,
      'accounts',
      () => accounts.value.map((e) => e.toJson()).toList(),
    );
  }

  static void detachAutoSave() {
    _autoSaveListeners.forEach((notifier, listener) {
      notifier.removeListener(listener);
    });
    _autoSaveListeners.clear();
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
    serverHost.value = _defaults['server_host'] ?? '127.0.0.1';
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
    if (PlatformService().isRemote) {
      await APIService.regenerateApiKey();
      return;
    }
    RequestNewApiKey().sendSignalToRust();
    final signal = await NewApiKey.rustSignalStream.first;
    serverApiKey.value = signal.message.key;
  }

  static Future<void> restartServer() async {
    if (PlatformService().isRemote) {
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
    if (PlatformService().isRemote) {
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

  static Future<String> _hashPassword(String plainText) async {
    if (plainText.isEmpty) return '';
    try {
      if (PlatformService().isRemote) {
        final hashed = await APIService.hashPassword(plainText, salt.value);
        if (hashed != null) return hashed;
      } else {
        final id = DateTime.now().microsecondsSinceEpoch.toString();
        final stream = HashingOutput.rustSignalStream.where(
          (signal) => signal.message.id == id,
        );
        HashPassword(
          id: id,
          plainText: plainText,
          salt: salt.value,
        ).sendSignalToRust();
        final signal = await stream.first;
        if (signal.message.hashedText != null) {
          return signal.message.hashedText!;
        }
      }
      return plainText;
    } catch (e) {
      log("Hashing error: $e", isError: true);
      return plainText;
    }
  }

  static Future<void> loadFromBackend() async {
    if (!PlatformService().isRemote) return;
    final data = await APIService.getSettings();
    if (data != null) {
      await _applyFromJson(data);
    } else {
      log('Failed to load settings from backend', isError: true);
    }
  }

  static Future<void> _saveToBackend() async {
    final jsonMap = await _toJson();
    jsonMap.remove('accounts');
    if (PlatformService().isRemote) {
      jsonMap.remove('server_host');
      jsonMap.remove('server_port');
    }
    final success = await APIService.saveSettings(jsonMap);
    if (!success) {
      log('Failed to save settings to backend', isError: true);
    }
  }

  static void addAccount(Account account) {
    // Check if account already exists with same host and port
    final index = accounts.value.indexWhere(
      (a) => a.host == account.host && a.port == account.port,
    );
    if (index != -1) {
      // Update existing
      final newAccounts = List<Account>.from(accounts.value);
      newAccounts[index] = account;
      accounts.value = newAccounts;
    } else {
      accounts.value = [...accounts.value, account];
    }
  }

  static void removeAccount(Account account) {
    accounts.value = accounts.value
        .where((a) => !(a.host == account.host && a.port == account.port))
        .toList();
  }

  static Future<void> switchAccount(Account account) async {
    isLoggedIn.value = false;
    detachAutoSave();
    serverHost.value = account.host;
    serverPort.value = account.port;
    username.value = account.username;
    serverApiKey.value = account.apiKey;
    attachAutoSave();
    APIService.restartPolling();
  }

  static Future<void> switchToLocal() async {
    if (kIsWeb) return;
    if (PlatformService().isRemote) {
      isLoggedIn.value = false;
    }
    detachAutoSave();
    final configExists = await _ioService.fileExists(configPath);
    if (configExists) {
      final Map<String, dynamic> data = jsonDecode(
        await _ioService.readFile(configPath),
      );
      serverHost.value =
          data['server_host'] ?? (_defaults['server_host'] ?? '127.0.0.1');
      serverPort.value =
          data['server_port'] ?? (_defaults['server_port'] ?? 8080);
      await _applyFromJson(data);
    } else {
      await applyDefaultSettings();
    }
    attachAutoSave();
    APIService.restartPolling();
  }
}
