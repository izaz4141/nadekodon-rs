import 'package:flutter/foundation.dart';

import 'package:nadekodon/utils/api_service/api_service.dart' as http_impl;
import 'package:nadekodon/utils/bridge/contract.dart';
import 'package:nadekodon/utils/platform_service.dart';
import 'package:nadekodon/utils/rinf_service/rinf_service.dart'
    show
        AddDownloadRequest,
        DownloadList,
        DownloadDetails,
        UrlQueryOutput,
        YtdlQueryOutput,
        YtdlFormat,
        CategoryDisplay;
import 'package:nadekodon/utils/rinf_service/rinf_service.dart' as rinf_impl;
import 'package:nadekodon/utils/system_service.dart';

export 'package:nadekodon/utils/rinf_service/rinf_service.dart'
    show
        DownloadList,
        DownloadGlance,
        DownloadDetails,
        PartInfo,
        AddDownloadRequest,
        UrlQueryOutput,
        YtdlQueryOutput,
        YtdlItem,
        YtdlFormat,
        CategoryDisplay;

/// Bridge facade between the HTTP (`api_service`) and native rinf
/// (`rinf_service`) implementations of [`ApiServiceContract`].
///
/// Keeps the legacy static surface so the existing call sites work unchanged.
/// The active implementation is selected lazily based on the platform/mode:
/// web and remote hosts use [`HttpApiService`], native local builds use
/// [`RinfApiService`]. `restartPolling()` re-evaluates the choice, so switching
/// accounts (local <-> remote) changes implementation on the next call.
class BridgeService {
  static final ValueNotifier<bool> isOnline = http_impl.HttpTransport.isOnline;
  static final ValueNotifier<String?> serverVersion =
      http_impl.HttpTransport.serverVersion;

  static ApiServiceContract? _impl;
  static ApiServiceContract? _localImpl;
  static bool _httpMode = false;

  static ApiServiceContract get impl {
    final httpMode = kIsWeb || PlatformService().isRemote;
    if (_impl == null || httpMode != _httpMode) {
      _httpMode = httpMode;
      _impl = httpMode
          ? http_impl.HttpApiService()
          : rinf_impl.RinfApiService();
    }
    return _impl!;
  }

  /// Always the local rinf implementation, regardless of the active host.
  static ApiServiceContract get localImpl =>
      _localImpl ??= rinf_impl.RinfApiService();

  static Future<void> init() => impl.init();

  static void dispose() => impl.dispose();

  // Native runtime / obfuscation. Routed through the local rinf implementation
  // so the local daemon/runtime is always driven; native call sites guard on
  // `!kIsWeb`.
  static Future<void> initNativeRuntime() => localImpl.initNativeRuntime();

  static void shutdownNative() => localImpl.shutdownNative();

  static Stream<({String level, String message})> get rustLogMessages =>
      localImpl.rustLogMessages;

  static Future<void> updateSettings({
    String? downloadDir,
    int? speedLimit,
    int? downloadThreads,
    int? concurrencyLimit,
    int? downloadTimeout,
    int? downloadRetries,
    double? seedingRatio,
    int? seedingTime,
    int? stalledTime,
  }) => localImpl.updateSettings(
    downloadDir: downloadDir,
    speedLimit: speedLimit,
    downloadThreads: downloadThreads,
    concurrencyLimit: concurrencyLimit,
    downloadTimeout: downloadTimeout,
    downloadRetries: downloadRetries,
    seedingRatio: seedingRatio,
    seedingTime: seedingTime,
    stalledTime: stalledTime,
  );

  static Future<String> x0(String input) => localImpl.x0(input);

  static Future<String> d0(String input) => localImpl.d0(input);

  static Future<String?> encryptKey(String plainKey, String? masterKey) =>
      localImpl.encryptKey(plainKey, masterKey);

  static Future<String?> decryptKey(String encryptedKey, String? masterKey) =>
      localImpl.decryptKey(encryptedKey, masterKey);

  static String get baseUrl => impl.baseUrl;

  static String wrapImageUrl(String externalUrl) =>
      impl.wrapImageUrl(externalUrl);

  // live/push streams
  static Stream<AddDownloadRequest> get addDownloadRequests =>
      impl.addDownloadRequests;

  static Stream<DownloadList> get downloadListStream => impl.downloadListStream;

  static void restartPolling() {
    _impl = null;
    http_impl.HttpTransport.restartPolling();
  }

  static Future<bool> login({
    required String username,
    required String password,
  }) => impl.login(username: username, password: password);

  static Future<String?> testLogin({
    required String host,
    required int port,
    required String username,
    required String password,
  }) => impl.testLogin(
    host: host,
    port: port,
    username: username,
    password: password,
  );

  static Future<bool> regenerateApiKey() => impl.regenerateApiKey();

  static Future<String?> hashPassword(String plainText) =>
      impl.hashPassword(plainText);

  static Future<bool> changeCredentials({
    required String currentPassword,
    String? newUsername,
    String? newPassword,
    int? serverPort,
  }) => impl.changeCredentials(
    currentPassword: currentPassword,
    newUsername: newUsername,
    newPassword: newPassword,
    serverPort: serverPort,
  );

  static Future<bool> verifyPassword(String password) =>
      impl.verifyPassword(password);

  static Future<String?> encrypt(String plainText) => impl.encrypt(plainText);

  static Future<String?> decrypt(String encryptedText) =>
      impl.decrypt(encryptedText);

  static Future<String?> getServerVersion() => impl.getServerVersion();

  static Future<Map<String, dynamic>?> getSettings() => impl.getSettings();

  static Future<bool> saveSettings(Map<String, dynamic> settings) =>
      impl.saveSettings(settings);

  static Future<bool> restartServer() => impl.restartServer();
  static Future<DownloadList?> getDownloadList({
    String? id,
    int offsetIndex = 0,
    int before = 0,
    int after = 0,
    List<String> statuses = const [],
    int? tag,
    String? searchQuery,
    int? sortBy,
    bool? ascending,
    List<String> categories = const [],
  }) => impl.getDownloadList(
    id: id,
    offsetIndex: offsetIndex,
    before: before,
    after: after,
    statuses: statuses,
    tag: tag,
    searchQuery: searchQuery,
    sortBy: sortBy,
    ascending: ascending,
    categories: categories,
  );

  static Future<DownloadDetails?> getDownloadDetails(String id) =>
      impl.getDownloadDetails(id);

  static String getDownloadUrl(String id) => impl.getDownloadUrl(id);

  static Future<bool> addDownload({
    String? url,
    required String dest,
    bool isYtdl = false,
    YtdlFormat? videoFormat,
    YtdlFormat? audioFormat,
    String? cookie,
    String? userAgent,
    String? referer,
    String? category,
    bool forceLocal = false,
  }) => (forceLocal ? localImpl : impl).addDownload(
    url: url,
    dest: dest,
    isYtdl: isYtdl,
    videoFormat: videoFormat,
    audioFormat: audioFormat,
    cookie: cookie,
    userAgent: userAgent,
    referer: referer,
    category: category,
  );

  static Future<bool> pauseDownload(String id) => impl.pauseDownload(id);

  static Future<bool> resumeDownload(String id) => impl.resumeDownload(id);

  static Future<bool> updateUrl(String id, String newUrl) =>
      impl.updateUrl(id, newUrl);

  static Future<bool> cancelDownload(String id) => impl.cancelDownload(id);

  static Future<bool> deleteDownload(String id, bool deleteFile) =>
      impl.deleteDownload(id, deleteFile);

  static Future<List<CategoryDisplay>?> getCategories({String? id}) =>
      impl.getCategories(id: id);

  static Future<bool> updateCategories(List<CategoryDisplay> categories) =>
      impl.updateCategories(categories);

  static Future<UrlQueryOutput?> queryUrl({
    String? id,
    required String url,
    String? cookie,
    String? userAgent,
    String? referer,
    bool forceLocal = false,
  }) => (forceLocal ? localImpl : impl).queryUrl(
    id: id,
    url: url,
    cookie: cookie,
    userAgent: userAgent,
    referer: referer,
  );

  static Future<YtdlQueryOutput?> queryYtdl({
    String? id,
    required String url,
    bool forceLocal = false,
  }) => (forceLocal ? localImpl : impl).queryYtdl(id: id, url: url);

  static Future<String?> getCurrentVersion(String app) =>
      impl.getCurrentVersion(app);

  static Future<VersionInfo?> getLatestVersion(
    String owner,
    String repo, {
    bool nightly = false,
    bool atomic = true,
  }) => impl.getLatestVersion(owner, repo, nightly: nightly, atomic: atomic);

  static Future<String?> compareVersions(List<String> versions) =>
      impl.compareVersions(versions);
}
