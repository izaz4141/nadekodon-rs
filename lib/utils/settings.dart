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
import 'package:nadekodon/utils/system_service.dart';
import 'package:nadekodon/utils/helper.dart';
import 'package:nadekodon/models/account.dart';

class SettingsManager {
  static const String masterKeyFile = 'master.key';
  static late IOService _ioService;
  static late String configPath;
  static bool isFirstRun = false;
  static Map<String, dynamic> defaults = {};

  // Your ValueNotifiers
  static final retreatToTray = ValueNotifier<bool>(true);
  static final downloadFolder = ValueNotifier<String>('');
  static final serverHost = ValueNotifier<String>('127.0.0.1');
  static final serverPort = ValueNotifier<int>(8080);
  static final serverApiKey = ValueNotifier<String>('');
  static final encryptedServerApiKey = ValueNotifier<String>('');
  static final username = ValueNotifier<String>('');
  static final password = ValueNotifier<String>('');
  static final hashedPassword = ValueNotifier<String>('');
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
  static final stalledTime = ValueNotifier<int>(30);

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
      defaults = json.decode(response);
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
          data['server_host'] ?? (defaults['server_host'] ?? '127.0.0.1');
      serverPort.value =
          data['server_port'] ?? (defaults['server_port'] ?? 8080);
      await _applyFromJson(data);
      await _saveAll();
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
        json['retreat_to_tray'] ?? defaults['retreat_to_tray'];
    downloadFolder.value = json['download_folder'] ?? '';

    final isRemote = PlatformService().isRemote;
    final storedApiKey = json['server_api_key'] as String? ?? '';

    if (!isRemote) {
      if (storedApiKey.isEmpty) {
        await regenerateApiKey();
      } else {
        final configDir = await _ioService.getConfigDir();
        final masterKeyPath = '$configDir/$masterKeyFile';
        final masterKeyExists = await _ioService.fileExists(masterKeyPath);
        String? masterKey;
        if (masterKeyExists) {
          final encoded = await _ioService.readFile(masterKeyPath);
          masterKey = await d0(encoded);
        }
        if (masterKey != null) {
          if (storedApiKey.startsWith('NDK:')) {
            final decrypted = await decryptKey(storedApiKey, masterKey);
            if (decrypted != null) {
              serverApiKey.value = decrypted;
              encryptedServerApiKey.value = storedApiKey;
            } else {
              await regenerateApiKey();
            }
          } else if (storedApiKey.isNotEmpty) {
            final encrypted = await encryptKey(storedApiKey, masterKey);
            if (encrypted != null) {
              serverApiKey.value = storedApiKey;
              encryptedServerApiKey.value = encrypted;
              saveChanged('server_api_key', encrypted);
            } else {
              await regenerateApiKey();
            }
          } else {
            await regenerateApiKey();
          }
        } else {
          await regenerateApiKey();
        }
      }
    }

    if (json.containsKey('salt')) {
      salt.value = json['salt'];
      if (salt.value.isEmpty) {
        await _generateSalt();
      }
    }
    if (json.containsKey('username')) {
      username.value = json['username'] ?? defaults['username'];
    }

    if (!isRemote) {
      final encodedPassword = json['password'] as String?;
      if (encodedPassword != null && encodedPassword.isNotEmpty) {
        password.value = encodedPassword;
        hashedPassword.value = encodedPassword;
      } else {
        password.value = await hashPassword(defaults['password']);
        hashedPassword.value = password.value;
      }
    }

    // Speed Scheduler
    speedLimit.value = (json['speed_limit'] ?? defaults['speed_limit'])
        .toDouble();
    speedMode.value =
        SpeedMode.values[json['speed_mode'] ?? defaults['speed_mode']];
    if (json['speed_schedule'] != null) {
      speedSchedule.value = (json['speed_schedule'] as List)
          .map((e) => ScheduleRule.fromJson(e))
          .toList();
    }

    downloadThreads.value =
        json['download_threads'] ?? defaults['download_threads'];
    concurrencyLimit.value =
        json['concurrency_limit'] ?? defaults['concurrency_limit'];
    downloadTimeout.value =
        json['download_timeout'] ?? defaults['download_timeout'];
    downloadRetries.value =
        json['download_retries'] ?? defaults['download_retries'];

    seedingRatio.value = (json['seeding_ratio'] ?? defaults['seeding_ratio'])
        .toDouble();
    seedingTime.value = json['seeding_time'] ?? defaults['seeding_time'];
    stalledTime.value = json['stalled_time'] ?? defaults['stalled_time'];

    // Theme Settings
    if (json['theme_mode'] != null) {
      themeMode.value = ThemeMode.values[json['theme_mode']];
    } else if (defaults['theme_mode'] != null) {
      themeMode.value = ThemeMode.values[defaults['theme_mode']];
    }
    useDynamicColor.value =
        json['use_dynamic_color'] ?? defaults['use_dynamic_color'];
    customColor.value = json['custom_color'] ?? defaults['custom_color'];
    checkNightly.value = json['check_nightly'] ?? defaults['check_nightly'];
    if (json.containsKey('require_login')) {
      requireLogin.value = json['require_login'] ?? false;
    }

    if (json['accounts'] != null) {
      final accountList = <Account>[];
      for (final accJson in json['accounts']) {
        accountList.add(await Account.fromJson(accJson));
      }
      accounts.value = accountList;
    }
  }

  static Future<Map<String, dynamic>> _toJson() async => {
    'retreat_to_tray': retreatToTray.value,
    'download_folder': downloadFolder.value,
    'server_host': serverHost.value,
    'server_port': serverPort.value,
    'server_api_key': encryptedServerApiKey.value,
    'salt': salt.value,
    'username': username.value,
    'password': hashedPassword.value,
    'speed_limit': speedLimit.value,
    'speed_mode': speedMode.value.index,
    'speed_schedule': speedSchedule.value.map((e) => e.toJson()).toList(),
    'download_threads': downloadThreads.value,
    'concurrency_limit': concurrencyLimit.value,
    'download_timeout': downloadTimeout.value,
    'stalled_time': stalledTime.value,
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

  static Future<void> reloadConfig() async {
    if (PlatformService().isRemote) return await loadFromBackend();

    final configDir = await _ioService.getConfigDir();
    configPath = '$configDir/config.json';
    final configExists = await _ioService.fileExists(configPath);

    if (configExists) {
      final Map<String, dynamic> data = jsonDecode(
        await _ioService.readFile(configPath),
      );
      serverHost.value =
          data['server_host'] ?? (defaults['server_host'] ?? '127.0.0.1');
      serverPort.value =
          data['server_port'] ?? (defaults['server_port'] ?? 8080);
      await _applyFromJson(data);
    }
  }

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

  static Future<void> saveChanged(String key, dynamic value) async {
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
      final hashed = await hashPassword(value);
      hashedPassword.value = hashed;
      data[key] = hashed;
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
          saveChanged(key, getValue != null ? getValue() : n.value);
      n.addListener(listener);
      _autoSaveListeners[n] = listener;
    }

    add(retreatToTray, 'retreat_to_tray');
    add(downloadFolder, 'download_folder');
    add(serverHost, 'server_host');
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
    add(stalledTime, 'stalled_time');
    add(themeMode, 'theme_mode', () => themeMode.value.index);
    add(useDynamicColor, 'use_dynamic_color');
    add(customColor, 'custom_color');
    add(checkNightly, 'check_nightly');
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
      case 'stalled_time':
        UpdateSettings(
          stalledTime: Uint64.fromBigInt(BigInt.from(value)),
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
      stalledTime: Uint64.fromBigInt(BigInt.from(stalledTime.value)),
    ).sendSignalToRust();
  }

  static void sendSpeedLimit(double value) {
    if (kIsWeb) return;
    UpdateSettings(
      speedLimit: Uint64.fromBigInt(BigInt.from((value * 1024 * 1024).round())),
    ).sendSignalToRust();
  }

  static Future<void> applyDefaultSettings() async {
    retreatToTray.value = defaults['retreat_to_tray'] ?? true;
    // downloadFolder is usually not reset to default from asset as it's environment dependent
    username.value = defaults['username'];
    password.value = await hashPassword(defaults['password']);

    if (salt.value.isEmpty) {
      await _generateSalt();
    }
    serverHost.value = defaults['server_host'] ?? '127.0.0.1';
    serverPort.value = defaults['server_port'] ?? 8080;
    speedLimit.value = (defaults['speed_limit'] ?? 0.0).toDouble();
    downloadThreads.value = defaults['download_threads'] ?? 8;
    concurrencyLimit.value = defaults['concurrency_limit'] ?? 3;
    downloadTimeout.value = defaults['download_timeout'] ?? 30;
    stalledTime.value = defaults['stalled_time'] ?? 30;
    downloadRetries.value = defaults['download_retries'] ?? 5;
    seedingRatio.value = (defaults['seeding_ratio'] ?? 1.0).toDouble();
    seedingTime.value = defaults['seeding_time'] ?? 30;

    if (defaults['theme_mode'] != null) {
      themeMode.value = ThemeMode.values[defaults['theme_mode']];
    }
    useDynamicColor.value = defaults['use_dynamic_color'] ?? true;
    customColor.value = defaults['custom_color'] ?? 0xFFFF4081;
    checkNightly.value = defaults['check_nightly'] ?? false;

    speedMode.value = SpeedMode.values[defaults['speed_mode'] ?? 0];
    speedSchedule.value = [];
  }

  static Future<String> getDatabasePath() async {
    return _ioService.getDatabasePath();
  }

  static Future<String> getTorrentPersistencePath() async {
    return _ioService.getTorrentPersistencePath();
  }

  static Future<String?> decryptKey(
    String encryptedKey,
    String masterKey,
  ) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final stream = DecryptResponse.rustSignalStream.where(
      (signal) => signal.message.id == id,
    );
    DecryptRequest(
      id: id,
      encryptedKey: encryptedKey,
      masterKey: masterKey,
    ).sendSignalToRust();
    try {
      final signal = await stream.first;
      return signal.message.decryptedKey.isNotEmpty
          ? signal.message.decryptedKey
          : null;
    } catch (e) {
      log('Failed to decrypt API key: $e', isError: true);
      return null;
    }
  }

  static Future<String?> encryptKey(
    String plainKey,
    String? existingMasterKey,
  ) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final stream = EncryptResponse.rustSignalStream.where(
      (signal) => signal.message.id == id,
    );
    EncryptRequest(
      id: id,
      plainKey: plainKey,
      masterKey: existingMasterKey,
    ).sendSignalToRust();
    try {
      final signal = await stream.first;
      return signal.message.encryptedKey.isNotEmpty
          ? signal.message.encryptedKey
          : null;
    } catch (e) {
      log('Failed to encrypt key: $e', isError: true);
      return null;
    }
  }

  static Future<void> regenerateApiKey() async {
    if (PlatformService().isRemote) {
      await APIService.regenerateApiKey();
      return;
    }
    final configDir = await _ioService.getConfigDir();
    final masterKeyPath = '$configDir/$masterKeyFile';
    final masterKeyExists = await _ioService.fileExists(masterKeyPath);
    String? existingMasterKey;
    if (masterKeyExists) {
      final encoded = await _ioService.readFile(masterKeyPath);
      existingMasterKey = await d0(encoded);
    }
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final stream = NewApiKey.rustSignalStream.where(
      (signal) => signal.message.id == id,
    );
    RequestNewApiKey(id: id, masterKey: existingMasterKey).sendSignalToRust();
    final signal = await stream.first;

    final encodedKey = await x0(signal.message.masterKey);
    await _ioService.writeFile(masterKeyPath, encodedKey);
    await _ioService.setPermissions(masterKeyPath, '0600');
    serverApiKey.value = signal.message.decryptedApiKey;
    encryptedServerApiKey.value = signal.message.encryptedApiKey;
    saveChanged('server_api_key', signal.message.encryptedApiKey);
  }

  static Future<void> restartServer() async {
    if (PlatformService().isRemote) {
      await APIService.restartServer();
      return;
    }
    final masterKey = await getMasterKey();
    StartServer(
      port: serverPort.value,
      apiKey: serverApiKey.value,
      masterKey: masterKey!,
      username: username.value,
      password: password.value,
      configPath: configPath,
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

  static Future<String> hashPassword(String plainText) async {
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
      jsonMap.remove('require_login');
    }
    final success = await APIService.saveSettings(jsonMap);
    if (!success) {
      log('Failed to save settings to backend', isError: true);
    }
  }

  static void addAccount(Account account) {
    final index = accounts.value.indexWhere(
      (a) => a.host == account.host && a.port == account.port,
    );
    if (index != -1) {
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

    final masterKey = await getMasterKey();
    if (masterKey != null && account.apiKey.startsWith('NDK:')) {
      final decrypted = await decryptKey(account.apiKey, masterKey);
      serverApiKey.value = decrypted ?? account.apiKey;
    } else {
      serverApiKey.value = account.apiKey;
    }
    encryptedServerApiKey.value = account.encryptedApiKey;

    APIService.isOnline.value = false;
    APIService.serverVersion.value = null;
    SystemService().refreshVersions();
    await loadFromBackend();
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
          data['server_host'] ?? (defaults['server_host'] ?? '127.0.0.1');
      serverPort.value =
          data['server_port'] ?? (defaults['server_port'] ?? 8080);
      await _applyFromJson(data);
    } else {
      await applyDefaultSettings();
    }
    APIService.isOnline.value = false;
    APIService.serverVersion.value = null;
    SystemService().refreshVersions();
    attachAutoSave();
    APIService.restartPolling();
  }
}
