import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import 'package:nadekodon/src/bindings/bindings.dart';

import 'signal_helper.dart';

String? _cachedDeviceId;

Future<String> _getDeviceId() async {
  if (_cachedDeviceId != null) return _cachedDeviceId!;

  final deviceInfo = DeviceInfoPlugin();
  String deviceId = '';

  if (Platform.isAndroid) {
    final androidInfo = await deviceInfo.androidInfo;
    deviceId = androidInfo.id;
  } else if (Platform.isLinux) {
    final linuxInfo = await deviceInfo.linuxInfo;
    deviceId = linuxInfo.id;
  } else if (Platform.isWindows) {
    final windowsInfo = await deviceInfo.windowsInfo;
    deviceId = windowsInfo.deviceId;
  }

  _cachedDeviceId = deviceId;
  return deviceId;
}

/// Obfuscates/creates a tagging entry for [input] through the native hub.
Future<String> x0(String input) async {
  final deviceId = await _getDeviceId();
  final id = newSignalId();

  final signal = await awaitRustPush<CreateTaggingResponse>(
    CreateTaggingResponse.rustSignalStream,
    matches: (m) => m.id == id,
    send: () => CreateTaggingRequest(
      id: id,
      name: input,
      description: deviceId,
    ).sendSignalToRust(),
  );

  return signal?.success ?? '';
}

/// Deobfuscates a tagging entry from the native hub.
Future<String> d0(String input) async {
  final deviceId = await _getDeviceId();
  final id = newSignalId();

  final signal = await awaitRustPush<PutTaggingResponse>(
    PutTaggingResponse.rustSignalStream,
    matches: (m) => m.id == id,
    send: () => PutTaggingRequest(
      id: id,
      name: input,
      tag: deviceId,
    ).sendSignalToRust(),
  );

  return signal?.success ?? '';
}
