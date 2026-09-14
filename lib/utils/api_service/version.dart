import 'dart:convert';

import 'package:nadekodon/utils/logger.dart';
import 'package:nadekodon/utils/system_service.dart';

import 'http_client.dart';

mixin VersionHttpApi {
  Future<String?> getCurrentVersion(String app) async {
    try {
      final response = await HttpTransport.get(
        '/api/nadeko/version/current?app=$app',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['version'] as String?;
      }
    } catch (e) {
      log("Error getting current version: $e", isError: true);
    }
    return null;
  }

  Future<VersionInfo?> getLatestVersion(
    String owner,
    String repo, {
    bool nightly = false,
    bool atomic = true,
  }) async {
    try {
      final response = await HttpTransport.get(
        '/api/nadeko/version/latest?owner=$owner&repo=$repo&nightly=$nightly&atomic=$atomic',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['error'] != Null) {
          final version = VersionInfo.fromJson(data);
          return version;
        }
      }
    } catch (e) {
      log("Error getting latest version: $e", isError: true);
    }
    return null;
  }

  Future<String?> compareVersions(List<String> versions) async {
    try {
      final response = await HttpTransport.post(
        '/api/nadeko/version/compare',
        body: {'versions': versions},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['latest'] as String?;
      }
    } catch (e) {
      log("Error comparing versions: $e", isError: true);
    }
    return null;
  }
}
