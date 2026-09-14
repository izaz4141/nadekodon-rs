import 'dart:convert';

import 'package:nadekodon/utils/logger.dart';
import 'package:nadekodon/utils/rinf_service/rinf_service.dart';

import 'http_client.dart';

mixin DownloadHttpApi {
  Future<DownloadList?> getDownloadList({
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
  }) async {
    try {
      final requestId = id ?? newSignalId();
      final payload = {
        'id': requestId,
        'offset_index': offsetIndex,
        'before': before,
        'after': after,
        'statuses': statuses,
        'tag': ?tag,
        'search_query': ?searchQuery,
        'sort_by': ?sortBy,
        'ascending': ?ascending,
        'categories': categories,
      };

      final response = await HttpTransport.post(
        '/api/nadeko/download/list',
        body: payload,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        return DownloadList(
          id: data['id'] ?? requestId,
          list: (data['list'] as List)
              .map(
                (i) => DownloadGlance(
                  id: i['id'],
                  downloadType: i['download_type'],
                  name: i['name'],
                  dest: i['dest'],
                  totalSize: i['total_size'] != null
                      ? Uint64.fromBigInt(BigInt.from(i['total_size']))
                      : null,
                  downloaded: Uint64.fromBigInt(BigInt.from(i['downloaded'])),
                  uploaded: Uint64.fromBigInt(BigInt.from(i['uploaded'])),
                  dspeed: i['dspeed'].toDouble(),
                  uspeed: i['uspeed']?.toDouble(),
                  state: i['state'],
                  referer: i['referer'],
                ),
              )
              .toList(),
          totalCount: Uint64.fromBigInt(BigInt.from(data['total_count'])),
          startIndex: Uint64.fromBigInt(BigInt.from(data['start_index'])),
          tag: data['tag'],
        );
      }
    } catch (e) {
      log("Error fetching list: $e", isError: true);
    }
    return null;
  }

  String getDownloadUrl(String id) {
    return '${HttpTransport.baseUrl}/api/nadeko/download/file/$id';
  }

  Future<DownloadDetails?> getDownloadDetails(String id) async {
    try {
      final response = await HttpTransport.get(
        '/api/nadeko/download/details/$id',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return DownloadDetails(
          id: data['id'],
          name: data['name'],
          url: data['url'],
          dest: data['dest'],
          totalSize: data['total_size'] != null
              ? Uint64.fromBigInt(BigInt.from(data['total_size']))
              : null,
          downloaded: Uint64.fromBigInt(BigInt.from(data['downloaded'])),
          speed: data['speed'].toDouble(),
          state: data['state'],
          partInfo: (data['part_info'] as List)
              .map(
                (p) => PartInfo(
                  start: Uint64.fromBigInt(BigInt.from(p['start'])),
                  end: Uint64.fromBigInt(BigInt.from(p['end'])),
                  current: Uint64.fromBigInt(BigInt.from(p['current'])),
                ),
              )
              .toList(),
          uploaded: data['uploaded'] != null
              ? Uint64.fromBigInt(BigInt.from(data['uploaded']))
              : null,
          uploadSpeed: data['upload_speed']?.toDouble(),
          peers: data['peers'] != null
              ? Uint64.fromBigInt(BigInt.from(data['peers']))
              : null,
          ratio: data['ratio']?.toDouble(),
          eta: data['eta'],
          referer: data['referer'],
        );
      }
    } catch (e) {
      log("Error fetching details: $e", isError: true);
    }
    return null;
  }

  Future<bool> addDownload({
    String? url,
    required String dest,
    bool isYtdl = false,
    YtdlFormat? videoFormat,
    YtdlFormat? audioFormat,
    String? cookie,
    String? userAgent,
    String? referer,
    String? category,
  }) async {
    final payload = {
      'id': newSignalId(),
      'url': url,
      'dest': dest,
      'is_ytdl': isYtdl,
      'cookie': cookie,
      'user_agent': userAgent,
      'referer': referer,
      'category': category,
      if (videoFormat != null)
        'video_format': {
          'format_id': videoFormat.formatId,
          'ext': videoFormat.ext,
          'filesize': videoFormat.filesize?.toInt(),
          'url': videoFormat.url,
          'vcodec': videoFormat.vcodec,
          'acodec': videoFormat.acodec,
          'note': videoFormat.note,
        },
      if (audioFormat != null)
        'audio_format': {
          'format_id': audioFormat.formatId,
          'ext': audioFormat.ext,
          'filesize': audioFormat.filesize?.toInt(),
          'url': audioFormat.url,
          'vcodec': audioFormat.vcodec,
          'acodec': audioFormat.acodec,
          'note': audioFormat.note,
        },
    };

    return _sendAction('download/create', payload);
  }

  Future<bool> pauseDownload(String id) async {
    return _sendAction('download/pause', {'id': id});
  }

  Future<bool> resumeDownload(String id) async {
    return _sendAction('download/resume', {'id': id});
  }

  Future<bool> updateUrl(String id, String newUrl) async {
    return _sendAction('download/update-url', {'id': id, 'new_url': newUrl});
  }

  Future<bool> cancelDownload(String id) async {
    return _sendAction('download/cancel', {'id': id});
  }

  Future<bool> deleteDownload(String id, bool deleteFile) async {
    return _sendAction('download/delete', {
      'id': id,
      'delete_file': deleteFile,
    });
  }

  Future<bool> _sendAction(String action, Map<String, dynamic> body) async {
    try {
      final response = await HttpTransport.post(
        '/api/nadeko/$action',
        body: body,
      );
      return response.statusCode == 200;
    } catch (e) {
      log("Error sending action $action: $e", isError: true);
      return false;
    }
  }

  Future<List<CategoryDisplay>?> getCategories({String? id}) async {
    try {
      final requestId = id ?? newSignalId();
      final response = await HttpTransport.get(
        '/api/nadeko/download/categories?id=$requestId',
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final categories = data['categories'] as List?;
        return categories
            ?.map(
              (c) => CategoryDisplay(
                name: c['name'] as String,
                savePath: c['save_path'] as String?,
              ),
            )
            .toList();
      }
    } catch (e) {
      log("Get categories error: $e", isError: true);
    }
    return null;
  }

  Future<bool> updateCategories(List<CategoryDisplay> categories) async {
    try {
      final payload = {
        'id': newSignalId(),
        'categories': categories
            .map((c) => {'name': c.name, 'save_path': c.savePath})
            .toList(),
      };
      final response = await HttpTransport.post(
        '/api/nadeko/download/categories',
        body: payload,
      );
      return response.statusCode == 200;
    } catch (e) {
      log("Update categories error: $e", isError: true);
    }
    return false;
  }
}
