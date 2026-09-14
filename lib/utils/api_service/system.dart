import 'dart:convert';

import 'package:nadekodon/utils/logger.dart';

import 'http_client.dart';

mixin SystemHttpApi {
  Future<String?> getServerVersion() => HttpTransport.getServerVersion();

  Future<Map<String, dynamic>?> getSettings() async {
    try {
      final response = await HttpTransport.get('/api/nadeko/system/settings');
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      log("Error getting settings: $e", isError: true);
    }
    return null;
  }

  Future<bool> saveSettings(Map<String, dynamic> settings) async {
    try {
      final response = await HttpTransport.post(
        '/api/nadeko/system/settings',
        body: settings,
      );
      return response.statusCode == 200;
    } catch (e) {
      log("Error saving settings: $e", isError: true);
      return false;
    }
  }

  Future<bool> restartServer() async {
    try {
      final response = await HttpTransport.post('/api/nadeko/system/restart');
      if (response.statusCode == 200) {
        return true;
      }
      log(
        'Server restart failed: ${response.statusCode} ${response.body}',
        isError: true,
      );
      return false;
    } catch (e) {
      log("Server restart failed: $e", isError: true);
      return false;
    }
  }
}
