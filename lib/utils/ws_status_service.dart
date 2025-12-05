import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:nadekodon/utils/settings.dart';
import 'package:nadekodon/utils/logger.dart';

class WebsocketStatusService {
  static final ValueNotifier<bool> isOnline = ValueNotifier(false);
  static Timer? _timer;
  static WebSocket? _socket;

  static void init() {
    _startPolling();

    SettingsManager.serverPort.addListener(restartPolling);
    SettingsManager.serverApiKey.addListener(restartPolling);
  }

  static void _startPolling() {
    _timer?.cancel();
    Timer(const Duration(seconds: 5), () => _checkStatus());
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _checkStatus());
  }

  static void restartPolling() {
    _startPolling();
  }

  static Future<void> _checkStatus() async {
    try {
      final port = SettingsManager.serverPort.value;
      final apiKey = SettingsManager.serverApiKey.value;
      _socket = await WebSocket.connect('ws://127.0.0.1:$port/ws?key=$apiKey');
      isOnline.value = true;
      await _socket?.close();
    } catch (e) {
      log("Server is offline: $e", isError: true);
      isOnline.value = false;
    }
  }

  static void dispose() {
    _timer?.cancel();
    SettingsManager.serverPort.removeListener(restartPolling);
    SettingsManager.serverApiKey.removeListener(restartPolling);
  }
}
