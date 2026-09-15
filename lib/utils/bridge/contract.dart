import 'package:nadekodon/utils/rinf_service/rinf_service.dart';
import 'package:nadekodon/utils/system_service.dart';

/// The transport-agnostic API contract implemented by both
/// [`HttpApiService`] (HTTP) and `RinfApiService` (rinf FFI).
///
/// Live/push data is exposed as streams: the native hub pushes updates over
/// rust signals, while the HTTP implementation has no push channel and exposes
/// empty streams (any polling stays on the caller's side).
abstract class ApiServiceContract {
  // lifecycle
  Future<void> init();
  void dispose();
  String get baseUrl;

  // live/push streams
  Stream<AddDownloadRequest> get addDownloadRequests;
  Stream<DownloadList> get downloadListStream;

  // native runtime / obfuscation (no-op on HTTP; native call sites guard kIsWeb)
  Future<void> initNativeRuntime();
  void shutdownNative();
  Stream<({String level, String message})> get rustLogMessages;
  Future<String> x0(String input);
  Future<String> d0(String input);
  Future<String?> encryptKey(String plainKey, String? masterKey);
  Future<String?> decryptKey(String encryptedKey, String? masterKey);

  // auth
  Future<bool> login({required String username, required String password});
  Future<String?> testLogin({
    required String host,
    required int port,
    required String username,
    required String password,
  });
  Future<bool> regenerateApiKey();
  Future<String?> hashPassword(String plainText);
  Future<bool> changeCredentials({
    required String currentPassword,
    String? newUsername,
    String? newPassword,
    int? serverPort,
  });
  Future<bool> verifyPassword(String password);
  Future<String?> encrypt(String plainText);
  Future<String?> decrypt(String encryptedText);

  // system
  Future<String?> getServerVersion();
  Future<Map<String, dynamic>?> getSettings();
  Future<bool> saveSettings(Map<String, dynamic> settings);
  Future<bool> restartServer();
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
  });

  // download
  Future<DownloadList?> getDownloadList({
    String? id,
    int offsetIndex,
    int before,
    int after,
    List<String> statuses,
    int? tag,
    String? searchQuery,
    int? sortBy,
    bool? ascending,
    List<String> categories,
  });
  Future<DownloadDetails?> getDownloadDetails(String id);
  String getDownloadUrl(String id);
  Future<List<String>?> addDownload({
    String? url,
    required String dest,
    bool isYtdl,
    YtdlFormat? videoFormat,
    YtdlFormat? audioFormat,
    String? cookie,
    String? userAgent,
    String? referer,
    String? category,
  });
  Future<bool> pauseDownload(String id);
  Future<bool> resumeDownload(String id);
  Future<bool> updateUrl(String id, String newUrl);
  Future<bool> cancelDownload(String id);
  Future<bool> deleteDownload(String id, bool deleteFile);
  Future<List<CategoryDisplay>?> getCategories({String? id});
  Future<bool> updateCategories(List<CategoryDisplay> categories);

  // utils
  Future<UrlQueryOutput?> queryUrl({
    String? id,
    required String url,
    String? cookie,
    String? userAgent,
    String? referer,
  });
  Future<YtdlQueryOutput?> queryYtdl({String? id, required String url});
  String wrapImageUrl(String externalUrl);

  // version
  Future<String?> getCurrentVersion(String app);
  Future<VersionInfo?> getLatestVersion(
    String owner,
    String repo, {
    bool nightly,
    bool atomic,
  });
  Future<String?> compareVersions(List<String> versions);
}
