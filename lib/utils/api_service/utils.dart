import 'dart:convert';

import 'package:nadekodon/utils/logger.dart';
import 'package:nadekodon/utils/rinf_service/rinf_service.dart';

import 'http_client.dart';

mixin UtilsHttpApi {
  Future<UrlQueryOutput?> queryUrl({
    String? id,
    required String url,
    String? cookie,
    String? userAgent,
    String? referer,
  }) async {
    try {
      final requestId = id ?? newSignalId();
      final payload = {
        'id': requestId,
        'url': url,
        'cookie': cookie,
        'user_agent': userAgent,
        'referer': referer,
      };

      final response = await HttpTransport.post(
        '/api/nadeko/utils/query-url',
        body: payload,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return UrlQueryOutput(
          id: data['id'] ?? requestId,
          url: data['url'],
          name: data['name'],
          totalSize: data['total_size'] != null
              ? Uint64.fromBigInt(BigInt.from(data['total_size']))
              : null,
          acceptRanges: data['accept_ranges'],
          contentType: data['content_type'],
          isWebpage: data['is_webpage'],
          error: data['error'],
        );
      }
    } catch (e) {
      log("Error querying URL: $e", isError: true);
    }
    return UrlQueryOutput(
      id: id ?? newSignalId(),
      url: url,
      name: "",
      totalSize: null,
      acceptRanges: false,
      contentType: null,
      isWebpage: false,
      error: true,
    );
  }

  Future<YtdlQueryOutput?> queryYtdl({String? id, required String url}) async {
    try {
      final requestId = id ?? newSignalId();
      final response = await HttpTransport.post(
        '/api/nadeko/utils/query-ytdl',
        body: {'id': requestId, 'url': url},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        List<YtdlItem> parsedItems = [];
        if (data.containsKey('items') && data['items'] != null) {
          parsedItems = (data['items'] as List)
              .map(
                (i) => YtdlItem(
                  name: i['name'] ?? '',
                  thumbnail: i['thumbnail'],
                  videos: ((i['videos'] ?? []) as List)
                      .map(
                        (v) => YtdlFormat(
                          formatId: v['format_id'],
                          ext: v['ext'],
                          filesize: v['filesize'] != null
                              ? Uint64.fromBigInt(BigInt.from(v['filesize']))
                              : null,
                          url: v['url'],
                          vcodec: v['vcodec'],
                          acodec: v['acodec'],
                          note: v['note'] ?? '',
                        ),
                      )
                      .toList(),
                  audios: ((i['audios'] ?? []) as List)
                      .map(
                        (a) => YtdlFormat(
                          formatId: a['format_id'],
                          ext: a['ext'],
                          filesize: a['filesize'] != null
                              ? Uint64.fromBigInt(BigInt.from(a['filesize']))
                              : null,
                          url: a['url'],
                          vcodec: a['vcodec'],
                          acodec: a['acodec'],
                          note: a['note'] ?? '',
                        ),
                      )
                      .toList(),
                ),
              )
              .toList();
        } else {
          parsedItems = [
            YtdlItem(
              name: data['name'] ?? '',
              thumbnail: data['thumbnail'],
              videos: ((data['videos'] ?? []) as List)
                  .map(
                    (v) => YtdlFormat(
                      formatId: v['format_id'],
                      ext: v['ext'],
                      filesize: v['filesize'] != null
                          ? Uint64.fromBigInt(BigInt.from(v['filesize']))
                          : null,
                      url: v['url'],
                      vcodec: v['vcodec'],
                      acodec: v['acodec'],
                      note: v['note'] ?? '',
                    ),
                  )
                  .toList(),
              audios: ((data['audios'] ?? []) as List)
                  .map(
                    (a) => YtdlFormat(
                      formatId: a['format_id'],
                      ext: a['ext'],
                      filesize: a['filesize'] != null
                          ? Uint64.fromBigInt(BigInt.from(a['filesize']))
                          : null,
                      url: a['url'],
                      vcodec: a['vcodec'],
                      acodec: a['acodec'],
                      note: a['note'] ?? '',
                    ),
                  )
                  .toList(),
            ),
          ];
        }

        return YtdlQueryOutput(
          id: data['id'] ?? requestId,
          items: parsedItems,
          error: data['error'],
        );
      }
    } catch (e) {
      log("Error querying YTDL: $e", isError: true);
    }
    return YtdlQueryOutput(
      id: id ?? newSignalId(),
      items: [],
      error: "Connection error",
    );
  }

  String wrapImageUrl(String externalUrl) =>
      HttpTransport.wrapImageUrl(externalUrl);
}
