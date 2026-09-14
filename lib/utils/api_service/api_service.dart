import 'package:flutter/foundation.dart';

import 'package:nadekodon/utils/api_service/auth.dart';
import 'package:nadekodon/utils/api_service/download.dart';
import 'package:nadekodon/utils/api_service/http_client.dart';
import 'package:nadekodon/utils/api_service/system.dart';
import 'package:nadekodon/utils/api_service/utils.dart';
import 'package:nadekodon/utils/api_service/version.dart';
import 'package:nadekodon/utils/bridge/contract.dart';
import 'package:nadekodon/utils/rinf_service/rinf_service.dart';
import 'package:nadekodon/utils/settings.dart';

export 'http_client.dart' show HttpTransport;

/// The HTTP-based implementation of the [`ApiServiceContract`].
class HttpApiService
    with
        AuthHttpApi,
        DownloadHttpApi,
        SystemHttpApi,
        UtilsHttpApi,
        VersionHttpApi
    implements ApiServiceContract {
  @override
  Future<void> init() async {
    // Check for cookie on web
    if (kIsWeb) {
      final success = await login(username: '', password: '');
      if (success) {
        SettingsManager.isLoggedIn.value = true;
      }
    }

    await HttpTransport.init();
  }

  @override
  void dispose() => HttpTransport.dispose();

  @override
  String get baseUrl => HttpTransport.baseUrl;

  @override
  Stream<AddDownloadRequest> get addDownloadRequests => const Stream.empty();

  @override
  Stream<DownloadList> get downloadListStream => const Stream.empty();

  // Native runtime members are no-ops for the HTTP implementation; the native
  // call sites guard on `!kIsWeb` before invoking them.
  @override
  Future<void> initNativeRuntime() async {}

  @override
  void shutdownNative() {}

  @override
  Stream<({String level, String message})> get rustLogMessages =>
      const Stream.empty();

  @override
  Future<void> updateSettings({
    String? downloadDir,
    int? speedLimit,
    int? downloadThreads,
    int? concurrencyLimit,
    int? downloadTimeout,
    int? downloadRetries,
    double? seedingRatio,
    int? seedingTime,
    int? stalledTime,
  }) async {}

  @override
  Future<String> x0(String input) async => input;

  @override
  Future<String> d0(String input) async => input;

  @override
  Future<String?> encryptKey(String plainKey, String? masterKey) async => null;

  @override
  Future<String?> decryptKey(String encryptedKey, String? masterKey) async =>
      null;
}
