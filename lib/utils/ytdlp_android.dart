import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:nadekodon/utils/logger.dart';
import 'package:nadekodon/src/bindings/bindings.dart';

class YtDlpAndroid {
  static const MethodChannel _channel = MethodChannel(
    'id.glicole.nadekodon/ytdlp',
  );

  static Future<String?> getYtdlpVersion() async {
    try {
      final String? result = await _channel.invokeMethod('ytdlpGetVersion');
      if (result != null) {
        final rawJson = jsonDecode(result);
        return rawJson['version'] as String?;
      }
      return null;
    } catch (e) {
      log('Error getting yt-dlp version: $e', isError: true);
      return null;
    }
  }

  static Future<YtdlQueryOutput?> ytdlpExtractInfo(String url) async {
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
