import 'package:nadekodon/src/bindings/bindings.dart';
import 'package:nadekodon/utils/platform_service.dart';
import 'package:nadekodon/utils/ytdlp_android.dart';

import 'signal_helper.dart';

/// Native (rinf FFI) URL/yt-dlp query operations.
mixin UtilsRinfApi {
  Future<UrlQueryOutput?> queryUrl({
    String? id,
    required String url,
    String? cookie,
    String? userAgent,
    String? referer,
  }) async {
    final requestId = id ?? newSignalId();
    return awaitRustPush<UrlQueryOutput>(
      UrlQueryOutput.rustSignalStream,
      matches: (m) => m.id == requestId,
      send: () => QueryUrlRequest(
        id: requestId,
        url: url,
        cookie: cookie,
        userAgent: userAgent,
        referer: referer,
      ).sendSignalToRust(),
    );
  }

  Future<YtdlQueryOutput?> queryYtdl({String? id, required String url}) async {
    if (PlatformService.isAndroid) {
      return YtDlpAndroid.ytdlpExtractInfo(url);
    }
    final requestId = id ?? newSignalId();
    return awaitRustPush<YtdlQueryOutput>(
      YtdlQueryOutput.rustSignalStream,
      matches: (m) => m.id == requestId,
      send: () => QueryYtdlRequest(id: requestId, url: url).sendSignalToRust(),
    );
  }
}
