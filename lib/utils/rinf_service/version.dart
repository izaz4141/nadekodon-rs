import 'package:nadekodon/utils/api_service/api_service.dart';
import 'package:nadekodon/utils/system_service.dart';

final HttpApiService _http = HttpApiService();

/// Native version checks reroute to the HTTP implementation (they hit GitHub
/// through the local server anyway).
mixin VersionRinfApi {
  Future<String?> getCurrentVersion(String app) => _http.getCurrentVersion(app);

  Future<VersionInfo?> getLatestVersion(
    String owner,
    String repo, {
    bool nightly = false,
    bool atomic = true,
  }) => _http.getLatestVersion(owner, repo, nightly: nightly, atomic: atomic);

  Future<String?> compareVersions(List<String> versions) =>
      _http.compareVersions(versions);
}
