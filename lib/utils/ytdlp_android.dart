import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:nadekodon/utils/logger.dart';
import 'package:nadekodon/src/bindings/bindings.dart';

class YtDlpAndroid {
  static const MethodChannel _channel = MethodChannel(
    'id.glicole.nadekodon/ytdlp',
  );

  static Future<YtdlQueryOutput?> getVideoInfo(String url) async {
    try {
      log('Running yt-dlp for $url via Chaquopy');

      final String? result = await _channel.invokeMethod('ytdlpExtractInfo', {
        'url': url,
      });

      if (result != null) {
        final rawJson = jsonDecode(result);
        return _mapToYtdlQueryOutput(rawJson);
      } else {
        log('Output from Chaquopy was null', isError: true);
        return null;
      }
    } on PlatformException catch (e) {
      log('Error running yt-dlp via Chaquopy: ${e.message}', isError: true);
      return null;
    } catch (e) {
      log('Unexpected error running yt-dlp: $e', isError: true);
      return null;
    }
  }

  static void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onProgress') {
        try {
          final args = call.arguments as Map;
          final id = args['id'] as String;
          final dataStr = args['data'] as String;
          final data = jsonDecode(dataStr);

          final downloaded = (data['downloaded_bytes'] as num?)?.toInt() ?? 0;
          final total = (data['total_bytes'] as num?)?.toInt();
          final speed = (data['speed'] as num?)?.toInt() ?? 0;

          ReportDownloadProgress(
            id: id,
            downloaded: Uint64(BigInt.from(downloaded)),
            total: total != null ? Uint64(BigInt.from(total)) : null,
            speed: Uint64(BigInt.from(speed)),
            state: data['status'] ?? 'unknown',
          ).sendSignalToRust();
        } catch (e) {
          log('Error processing progress: $e', isError: true);
        }
      }
    });
  }

  static Future<void> downloadVideo(
    String url,
    String id,
    Map<String, dynamic> options,
  ) async {
    try {
      await _channel.invokeMethod('ytdlpDownload', {
        'url': url,
        'id': id,
        'options': jsonEncode(options),
      });
    } catch (e) {
      log('Error starting download: $e', isError: true);
      // Report error to Rust
      ReportDownloadProgress(
        id: id,
        downloaded: Uint64(BigInt.from(0)),
        total: null,
        speed: Uint64(BigInt.from(0)),
        state: 'error',
      ).sendSignalToRust();
    }
  }

  static YtdlQueryOutput _mapToYtdlQueryOutput(Map<String, dynamic> raw) {
    if (raw.containsKey('error')) {
      return YtdlQueryOutput(
        name: '',
        thumbnail: null,
        videos: [],
        audios: [],
        error: raw['error'],
      );
    }

    final String name = raw['title'] ?? 'Unknown';
    final String? thumbnail = raw['thumbnail'];
    final List<dynamic> formats = raw['formats'] ?? [];

    final videos = <YtdlFormat>[];
    final audios = <YtdlFormat>[];

    for (var f in formats) {
      final String formatId = f['format_id'] ?? '';
      final String ext = f['ext'] ?? '';
      final int? filesizeInt = f['filesize'];
      final Uint64? filesize = filesizeInt != null
          ? Uint64.fromBigInt(BigInt.from(filesizeInt))
          : null;
      final String url = f['url'] ?? '';
      final String? vcodec = f['vcodec'];
      final String? acodec = f['acodec'];
      final String note = f['format_note'] ?? '';

      final formatMap = YtdlFormat(
        formatId: formatId,
        ext: ext,
        filesize: filesize,
        url: url,
        vcodec: vcodec,
        acodec: acodec,
        note: note,
      );

      final bool hasVideo = vcodec != null && vcodec != 'none';
      final bool hasAudio = acodec != null && acodec != 'none';

      if (hasVideo) {
        videos.add(formatMap);
      } else if (hasAudio) {
        audios.add(formatMap);
      }
    }

    return YtdlQueryOutput(
      name: name,
      thumbnail: thumbnail,
      videos: videos,
      audios: audios,
      error: null,
    );
  }
}
