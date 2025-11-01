import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class SettingsManager {
  static late File _file;

  // Your ValueNotifiers
  static final retreatToTray = ValueNotifier<bool>(true);
  static final downloadFolder = ValueNotifier<String>('');
  static final serverPort = ValueNotifier<int>(8080);
  static final speedLimit = ValueNotifier<double>(2.0);
  static final downloadThread = ValueNotifier<int>(8);
  static final maxDownload = ValueNotifier<int>(3);

  /// Init config system (call at app startup)
  static Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    _file = File('${dir.path}/config.json');

    if (await _file.exists()) {
      final data = jsonDecode(await _file.readAsString());
      _applyFromJson(data);
      debugPrint('${dir.path}/config.json');
    } else {
      debugPrint("Initial Config");
      await _save(); // save defaults if no file
    }

    // Attach listeners so every change is persisted
    _attachAutoSave();
  }

  static void _applyFromJson(Map<String, dynamic> json) {
    retreatToTray.value = json['retreat_to_tray'] ?? true;
    downloadFolder.value = json['download_folder'] ?? '';
    serverPort.value = json['server_port'] ?? 8080;
    speedLimit.value = (json['speed_limit'] ?? 2.0).toDouble();
    downloadThread.value = json['download_thread'] ?? 8;
    maxDownload.value = json['max_download'] ?? 3;
  }

  static Map<String, dynamic> _toJson() => {
    'retreat_to_tray': retreatToTray.value,
    'download_folder': downloadFolder.value,
    'server_port': serverPort.value,
    'speed_limit': speedLimit.value,
    'download_thread': downloadThread.value,
    'max_download': maxDownload.value,
  };

  static Future<void> _save() async {
    await _file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_toJson()),
    );
  }

  static void _attachAutoSave() {
    for (var notifier in [
      retreatToTray,
      downloadFolder,
      serverPort,
      speedLimit,
      downloadThread,
      maxDownload,
    ]) {
      notifier.addListener(_save);
    }
  }
}
