import 'package:nadekodon/utils/api_service/api_service.dart';

final HttpApiService _http = HttpApiService();

/// Native system operations. Since the embedded hub always runs a local server,
/// status/settings/restart reroute to the HTTP implementation.
mixin SystemRinfApi {
  Future<String?> getServerVersion() => _http.getServerVersion();

  Future<Map<String, dynamic>?> getSettings() => _http.getSettings();

  Future<bool> saveSettings(Map<String, dynamic> settings) =>
      _http.saveSettings(settings);

  Future<bool> restartServer() => _http.restartServer();
}
