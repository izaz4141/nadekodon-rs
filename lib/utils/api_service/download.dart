import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nadekodon/utils/logger.dart';
import 'package:nadekodon/utils/rinf_service/rinf_service.dart';

import 'http_client.dart';

mixin DownloadHttpApi {
  Map<String, dynamic> _downloadListPayload({
    required String id,
    required int offsetIndex,
    required int before,
    required int after,
    required List<String> statuses,
    required int? tag,
    required String? searchQuery,
    required int? sortBy,
    required bool? ascending,
    required List<String> categories,
  }) {
    return {
      'id': id,
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
  }

  DownloadList _downloadListFromJson(
    Map<String, dynamic> data, {
    required String fallbackId,
  }) {
    final rawList = data['list'] as List? ?? const [];
    final list = rawList.map((item) {
      final i = item as Map<String, dynamic>;
      return DownloadGlance(
        id: i['id'],
        downloadType: i['download_type'],
        name: i['name'],
        dest: i['dest'],
        totalSize: i['total_size'] != null
            ? Uint64.fromBigInt(BigInt.from(i['total_size']))
            : null,
        downloaded: Uint64.fromBigInt(BigInt.from(i['downloaded'])),
        uploaded: Uint64.fromBigInt(BigInt.from(i['uploaded'])),
        dspeed: (i['dspeed'] as num).toDouble(),
        uspeed: (i['uspeed'] as num?)?.toDouble(),
        state: i['state'],
        referer: i['referer'],
      );
    }).toList();

    return DownloadList(
      id: data['id'] as String? ?? fallbackId,
      list: list,
      totalCount: Uint64.fromBigInt(BigInt.from(data['total_count'] ?? 0)),
      startIndex: Uint64.fromBigInt(BigInt.from(data['start_index'] ?? 0)),
      tag: data['tag'] as int?,
    );
  }

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
      final payload = _downloadListPayload(
        id: requestId,
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

      final response = await HttpTransport.post(
        '/api/nadeko/download/list',
        body: payload,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return _downloadListFromJson(data, fallbackId: requestId);
      }
    } catch (e) {
      log("Error fetching list: $e", isError: true);
    }
    return null;
  }

  /// Long-lived download list subscription.
  ///
  /// The server pushes the requested window as NDJSON frames instead of the
  /// client polling. Falls back to periodic one-shot requests against servers
  /// that do not expose the streaming endpoint yet.
  Stream<DownloadList> streamDownloadList({
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
    Duration interval = const Duration(milliseconds: 500),
  }) async* {
    final requestId = id ?? newSignalId();
    final payload = _downloadListPayload(
      id: requestId,
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

    var attempt = 0;

    while (true) {
      var receivedFrame = false;
      try {
        final stream = HttpTransport.postNdjson(
          '/api/nadeko/download/list/stream'
          '?interval_ms=${interval.inMilliseconds.clamp(100, 10000)}',
          body: payload,
          headers: const {'Accept': 'application/x-ndjson'},
        );

        await for (final line in stream) {
          final decoded = jsonDecode(line);
          if (decoded is! Map<String, dynamic>) continue;

          final frameId = decoded['id'];
          if (frameId != null && frameId != requestId) continue;

          final error = decoded['error'];
          if (error != null) {
            log("Download list stream error: $error", isError: true);
            continue;
          }

          receivedFrame = true;
          attempt = 0;
          yield _downloadListFromJson(decoded, fallbackId: requestId);
        }

        // A normal close (for example the 10-minute server lifetime cap)
        // reconnects immediately unless we never got a frame.
        if (!receivedFrame) attempt++;
      } on HttpStreamException catch (e) {
        if (e.statusCode == 404 || e.statusCode == 405) {
          log(
            "Download list stream unsupported; falling back to polling",
            isError: true,
          );
          yield* _pollDownloadList(
            id: requestId,
            offsetIndex: offsetIndex,
            before: before,
            after: after,
            statuses: statuses,
            tag: tag,
            searchQuery: searchQuery,
            sortBy: sortBy,
            ascending: ascending,
            categories: categories,
            interval: interval,
          );
          return;
        }

        if (e.statusCode == 401 || e.statusCode == 403) {
          log(
            "Download list stream unauthorized (${e.statusCode})",
            isError: true,
          );
          rethrow;
        }

        attempt++;
      } catch (e) {
        if (e is http.RequestAbortedException) return;
        log("Download list stream disconnected: $e", isError: true);
        attempt++;
      }

      await Future.delayed(_streamRetryDelay(attempt));
    }
  }

  Stream<DownloadList> _pollDownloadList({
    required String id,
    required int offsetIndex,
    required int before,
    required int after,
    required List<String> statuses,
    required int? tag,
    required String? searchQuery,
    required int? sortBy,
    required bool? ascending,
    required List<String> categories,
    required Duration interval,
  }) {
    final cancelSignal = Completer<void>();
    var cancelled = false;
    late final StreamController<DownloadList> controller;

    Future<void> cancellableDelay() {
      final done = Completer<void>();
      final timer = Timer(interval, () {
        if (!done.isCompleted) done.complete();
      });
      cancelSignal.future.then((_) {
        timer.cancel();
        if (!done.isCompleted) done.complete();
      });
      return done.future;
    }

    Future<void> poll() async {
      while (!cancelled) {
        final list = await getDownloadList(
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
        if (cancelled) return;
        if (list != null) controller.add(list);
        await cancellableDelay();
      }
    }

    controller = StreamController<DownloadList>(
      onListen: () => unawaited(poll()),
      onCancel: () {
        cancelled = true;
        if (!cancelSignal.isCompleted) cancelSignal.complete();
      },
    );

    return controller.stream;
  }

  Duration _streamRetryDelay(int attempt) {
    final exponent = attempt.clamp(0, 6);
    final milliseconds = (500 * (1 << exponent)).clamp(500, 30000);
    return Duration(milliseconds: milliseconds);
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

  Future<List<String>?> addDownload({
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

    try {
      final response = await HttpTransport.post(
        '/api/nadeko/download/create',
        body: payload,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final ids = data['download_ids'] as List?;
        return ids?.cast<String>();
      }
    } catch (e) {
      log("Error adding download: $e", isError: true);
    }
    return null;
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
