import 'dart:convert';

import 'package:nadekodon/src/bindings/bindings.dart';
import 'package:nadekodon/utils/helper.dart';
import 'package:nadekodon/utils/logger.dart';

import 'signal_helper.dart';

/// Persists a settings patch into this device's `config.json` via the hub.
/// Rust owns all writes; native-only (no hub on web).
Future<bool> writeLocalConfig(
  String configPath,
  Map<String, dynamic> settings,
) async {
  try {
    final masterKey = await getMasterKey();
    final id = newSignalId();
    final signal = await awaitRustPush<SaveLocalConfigResponse>(
      SaveLocalConfigResponse.rustSignalStream,
      matches: (m) => m.id == id,
      send: () => SaveLocalConfigRequest(
        id: id,
        configPath: configPath,
        masterKey: masterKey,
        settingsJson: jsonEncode(settings),
      ).sendSignalToRust(),
    );
    return signal?.success ?? false;
  } catch (e) {
    log("Error persisting local config: $e", isError: true);
    return false;
  }
}

/// Reads this device's `config.json` via the hub.
/// `success && settings == null` means the config does not exist yet.
Future<({bool success, String? error, Map<String, dynamic>? settings})>
readLocalConfig(String configPath) async {
  try {
    final id = newSignalId();
    final signal = await awaitRustPush<LoadLocalConfigResponse>(
      LoadLocalConfigResponse.rustSignalStream,
      matches: (m) => m.id == id,
      send: () => LoadLocalConfigRequest(
        id: id,
        configPath: configPath,
      ).sendSignalToRust(),
    );
    if (signal == null) {
      return (success: false, error: 'hub did not respond', settings: null);
    }
    Map<String, dynamic>? settings;
    final raw = signal.settingsJson;
    if (signal.success && raw != null && raw.isNotEmpty) {
      settings = jsonDecode(raw) as Map<String, dynamic>;
    }
    return (success: signal.success, error: signal.error, settings: settings);
  } catch (e) {
    log("Error reading local config: $e", isError: true);
    return (success: false, error: e.toString(), settings: null);
  }
}
