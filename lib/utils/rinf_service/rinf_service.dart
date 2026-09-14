import 'package:nadekodon/src/bindings/bindings.dart';
import 'package:nadekodon/utils/api_service/api_service.dart';
import 'package:nadekodon/utils/bridge/contract.dart';
import 'package:nadekodon/utils/rinf_service/auth.dart';
import 'package:nadekodon/utils/rinf_service/download.dart';
import 'package:nadekodon/utils/rinf_service/native.dart';
import 'package:nadekodon/utils/rinf_service/signal_helper.dart';
import 'package:nadekodon/utils/rinf_service/system.dart';
import 'package:nadekodon/utils/rinf_service/utils.dart';
import 'package:nadekodon/utils/rinf_service/version.dart';

export 'signal_helper.dart';
export 'tagging.dart' show x0, d0;
export 'package:nadekodon/src/bindings/bindings.dart';

/// The native (rinf FFI) implementation of the [`ApiServiceContract`].
///
/// Download/auth operations talk to the embedded hub directly via signals.
/// Operations where the local server (or GitHub) already answers over HTTP
/// reroute to [`HttpApiService`]. Live/push data (`addDownloadRequests`,
/// `downloadListStream`) comes from rust signals.
class RinfApiService
    with
        AuthRinfApi,
        DownloadRinfApi,
        NativeRinfApi,
        SystemRinfApi,
        UtilsRinfApi,
        VersionRinfApi
    implements ApiServiceContract {
  static final HttpApiService _http = HttpApiService();

  @override
  Stream<AddDownloadRequest> get addDownloadRequests =>
      AddDownloadRequest.rustSignalStream.map((pack) => pack.message);

  @override
  Stream<DownloadList> get downloadListStream =>
      DownloadList.rustSignalStream.map((pack) => pack.message);

  @override
  Future<void> init() async => HttpTransport.init();

  @override
  void dispose() => HttpTransport.dispose();

  @override
  String get baseUrl => _http.baseUrl;

  @override
  Future<bool> login({required String username, required String password}) =>
      _http.login(username: username, password: password);

  @override
  Future<String?> testLogin({
    required String host,
    required int port,
    required String username,
    required String password,
  }) => _http.testLogin(
    host: host,
    port: port,
    username: username,
    password: password,
  );

  @override
  Future<bool> changeCredentials({
    required String currentPassword,
    String? newUsername,
    String? newPassword,
    int? serverPort,
  }) => _http.changeCredentials(
    currentPassword: currentPassword,
    newUsername: newUsername,
    newPassword: newPassword,
    serverPort: serverPort,
  );

  @override
  Future<bool> verifyPassword(String password) =>
      _http.verifyPassword(password);

  @override
  String getDownloadUrl(String id) => _http.getDownloadUrl(id);

  @override
  String wrapImageUrl(String externalUrl) => _http.wrapImageUrl(externalUrl);
}
