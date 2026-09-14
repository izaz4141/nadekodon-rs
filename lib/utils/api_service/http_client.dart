import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:nadekodon/utils/logger.dart';
import 'package:nadekodon/utils/settings.dart';

/// Shared HTTP transport for the `api_service` implementation.
///
/// Keeps the URL/status state that the HTTP implementation needs and that the
/// bridge facade (`BridgeService`) exposes: `baseUrl`, the `isOnline` /
/// `serverVersion` notifiers and the status polling loop.
class HttpTransport {
  static final ValueNotifier<bool> isOnline = ValueNotifier(false);
  static final ValueNotifier<String?> serverVersion = ValueNotifier(null);

  static Timer? _timer;
  static Timer? _debounce;

  static String get baseUrl {
    if (kIsWeb) {
      return Uri.base.origin;
    }
    String host = SettingsManager.serverHost.value;
    if (!host.contains('://')) {
      host = 'http://$host';
    }
    final port = SettingsManager.serverPort.value;
    return '$host:$port';
  }

  static String wrapImageUrl(String externalUrl) {
    if (externalUrl.isEmpty) return externalUrl;
    if (!kIsWeb) return externalUrl;
    final encoded = Uri.encodeComponent(externalUrl);
    return '$baseUrl/api/nadeko/utils/img?url=$encoded';
  }

  static Map<String, String> _headers({
    Map<String, String>? extra,
    String? contentType,
  }) {
    return {
      'Content-Type': ?contentType,
      if (SettingsManager.serverApiKey.value.isNotEmpty)
        'X-API-Key': SettingsManager.serverApiKey.value,
      ...?extra,
    };
  }

  static Future<http.Response> get(
    String path, {
    Map<String, String>? headers,
  }) {
    return http.get(
      Uri.parse('$baseUrl$path'),
      headers: _headers(extra: headers),
    );
  }

  static Future<http.Response> post(
    String path, {
    dynamic body,
    Map<String, String>? headers,
  }) {
    return http.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers(
        extra: headers,
        contentType: body != null ? 'application/json' : null,
      ),
      body: body != null ? jsonEncode(body) : null,
    );
  }

  static Future<void> init() {
    _startPolling();
    SettingsManager.serverHost.addListener(restartPolling);
    SettingsManager.serverPort.addListener(restartPolling);
    SettingsManager.serverApiKey.addListener(restartPolling);
    return Future.value();
  }

  static void dispose() {
    _timer?.cancel();
    SettingsManager.serverHost.removeListener(restartPolling);
    SettingsManager.serverPort.removeListener(restartPolling);
    SettingsManager.serverApiKey.removeListener(restartPolling);
  }

  static void _startPolling() {
    _timer?.cancel();

    isOnline.value = false;
    serverVersion.value = null;

    _checkStatus();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _checkStatus());
  }

  static void restartPolling() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      _startPolling();
    });
  }

  static Future<void> _checkStatus() async {
    try {
      final response = await get('/api/nadeko/system/status');
      if (response.statusCode == 200) {
        isOnline.value = true;
        try {
          final data = jsonDecode(response.body);
          if (data is Map) {
            serverVersion.value = data['version'] as String?;
          }
        } catch (_) {
          // Fallback for non-JSON status response if any
        }
      } else {
        isOnline.value = false;
        serverVersion.value = null;
        log(
          "Server status check failed: ${response.statusCode} ${response.body}",
        );
      }
    } catch (e) {
      // Don't log typical connection refused errors as they spam when server is off
      if (isOnline.value) {
        log("Server status check failed: $e", isError: true);
      }
      isOnline.value = false;
      serverVersion.value = null;
    }
  }

  static Future<String?> getServerVersion() async {
    await _checkStatus();
    return serverVersion.value;
  }
}
