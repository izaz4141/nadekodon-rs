import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:flutter/foundation.dart';
import 'package:nadekodon/src/bindings/bindings.dart';
import 'package:nadekodon/utils/settings.dart';
import 'package:nadekodon/utils/logger.dart';

class APIService {
  static final ValueNotifier<bool> isOnline = ValueNotifier(false);
  static Timer? _timer;

  static Future<void> init() async {
    // Check for cookie on web
    if (kIsWeb) {
      final success = await login(username: '', password: '');
      if (success) {
        SettingsManager.isLoggedIn.value = true;
      }
    }

    _startPolling();

    SettingsManager.serverHost.addListener(restartPolling);
    SettingsManager.serverPort.addListener(restartPolling);
    SettingsManager.serverApiKey.addListener(restartPolling);

    isOnline.addListener(() {
      if (isOnline.value) {
        _tryDecryptPassword();
      }
    });
  }

  static Future<void> _tryDecryptPassword() async {
    final current = SettingsManager.password.value;
    if (current.contains('"iv":') && current.contains('"data":')) {
      final decrypted = await decryptPassword(
        current,
        SettingsManager.salt.value,
      );
      if (decrypted != null) {
        SettingsManager.password.value = decrypted;
      }
    }
  }

  static String get baseUrl {
    if (kIsWeb) {
      return Uri.base.origin;
    }
    String host = SettingsManager.serverHost.value;
    final port = SettingsManager.serverPort.value;
    return 'http://$host:$port';
  }

  static void _startPolling() {
    _timer?.cancel();
    _checkStatus();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _checkStatus());
  }

  static void restartPolling() {
    _startPolling();
  }

  static Future<bool> login({
    required String username,
    required String password,
  }) async {
    try {
      late final Map<String, dynamic> body;

      body = {'username': username, 'password': password};

      final response = await http.post(
        Uri.parse('$baseUrl/api/nadeko/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final returnedApiKey = data['api_key'];
        SettingsManager.loadFromBackend();

        if (returnedApiKey is String && returnedApiKey.isNotEmpty) {
          SettingsManager.serverApiKey.value = returnedApiKey;
          return true;
        }
      } else {
        log(
          'Login failed: ${response.statusCode} ${response.body}',
          isError: true,
        );
      }
    } catch (e) {
      log('Login error: $e', isError: true);
    }

    return false;
  }

  static Future<void> _checkStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/nadeko/status'),
        headers: {'X-API-Key': SettingsManager.serverApiKey.value},
      );

      if (response.statusCode == 200) {
        isOnline.value = true;
      } else {
        isOnline.value = false;
        log(
          "Server status check failed: ${response.statusCode}",
          isError: true,
        );
      }
    } catch (e) {
      // Don't log typical connection refused errors as they spam when server is off
      if (!isOnline.value) {
        // suppress
      } else {
        log("Server is offline: $e", isError: true);
      }
      isOnline.value = false;
    }
  }

  static Future<DownloadList?> getDownloadList({
    String? anchorId,
    int before = 0,
    int after = 0,
    List<String> statuses = const [],
    int? tag,
    String? searchQuery,
    int? sortBy,
    bool? ascending,
  }) async {
    try {
      final payload = {
        if (anchorId != null) 'anchor_id': anchorId,
        'before': before,
        'after': after,
        'statuses': statuses,
        if (tag != null) 'tag': tag,
        if (searchQuery != null) 'search_query': searchQuery,
        if (sortBy != null) 'sort_by': sortBy,
        if (ascending != null) 'ascending': ascending,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/api/nadeko/list'),
        headers: {
          'X-API-Key': SettingsManager.serverApiKey.value,
          'Content-Type': 'application/json',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        return DownloadList(
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

  static Future<DownloadDetails?> getDownloadDetails(String id) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/nadeko/details/$id'),
        headers: {'X-API-Key': SettingsManager.serverApiKey.value},
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

  static Future<bool> addDownload({
    String? url,
    required String dest,
    bool isYtdl = false,
    YtdlFormat? videoFormat,
    YtdlFormat? audioFormat,
    String? cookie,
    String? userAgent,
    String? referer,
  }) async {
    final payload = {
      'url': url,
      'dest': dest,
      'is_ytdl': isYtdl,
      'cookie': cookie,
      'user_agent': userAgent,
      'referer': referer,
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

    return _sendAction('do-download', payload);
  }

  static Future<UrlQueryOutput?> queryUrl({
    required String url,
    String? cookie,
    String? userAgent,
    String? referer,
  }) async {
    try {
      final payload = {
        'url': url,
        'cookie': cookie,
        'user_agent': userAgent,
        'referer': referer,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/api/nadeko/query-url'),
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': SettingsManager.serverApiKey.value,
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return UrlQueryOutput(
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
      url: url,
      name: "",
      totalSize: null,
      acceptRanges: false,
      contentType: null,
      isWebpage: false,
      error: true,
    );
  }

  static Future<YtdlQueryOutput?> queryYtdl({required String url}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/nadeko/query-ytdl'),
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': SettingsManager.serverApiKey.value,
        },
        body: jsonEncode({'url': url}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return YtdlQueryOutput(
          name: data['name'],
          thumbnail: data['thumbnail'],
          videos: (data['videos'] as List)
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
                  note: v['note'],
                ),
              )
              .toList(),
          audios: (data['audios'] as List)
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
                  note: a['note'],
                ),
              )
              .toList(),
          error: data['error'],
        );
      }
    } catch (e) {
      log("Error querying YTDL: $e", isError: true);
    }
    return YtdlQueryOutput(
      name: "",
      thumbnail: null,
      videos: [],
      audios: [],
      error: "Connection error",
    );
  }

  static Future<bool> pauseDownload(String id) async {
    return _sendAction('pause', {'id': id});
  }

  static Future<bool> resumeDownload(String id) async {
    return _sendAction('resume', {'id': id});
  }

  static Future<bool> updateUrl(String id, String newUrl) async {
    return _sendAction('update-url', {'id': id, 'new_url': newUrl});
  }

  static Future<bool> cancelDownload(String id) async {
    return _sendAction('cancel', {'id': id});
  }

  static Future<bool> deleteDownload(String id, bool deleteFile) async {
    return _sendAction('delete', {'id': id, 'delete_file': deleteFile});
  }

  static Future<bool> _sendAction(
    String action,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/nadeko/$action'),
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': SettingsManager.serverApiKey.value,
        },
        body: jsonEncode(body),
      );
      return response.statusCode == 200;
    } catch (e) {
      log("Error sending action $action: $e", isError: true);
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getSettings() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/nadeko/settings'),
        headers: {'X-API-Key': SettingsManager.serverApiKey.value},
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      log("Error getting settings: $e", isError: true);
    }
    return null;
  }

  static Future<bool> saveSettings(Map<String, dynamic> settings) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/nadeko/settings'),
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': SettingsManager.serverApiKey.value,
        },
        body: jsonEncode(settings),
      );
      return response.statusCode == 200;
    } catch (e) {
      log("Error saving settings: $e", isError: true);
      return false;
    }
  }

  static Future<String?> encryptPassword(String plainText, String salt) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/nadeko/encrypt'),
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': SettingsManager.serverApiKey.value,
        },
        body: jsonEncode({'plain_text': plainText, 'salt': salt}),
      );
      if (response.statusCode == 200) {
        return response.body;
      }
    } catch (e) {
      log("Error encrypting password: $e", isError: true);
    }
    return null;
  }

  static Future<String?> decryptPassword(String stored, String salt) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/nadeko/decrypt'),
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': SettingsManager.serverApiKey.value,
        },
        body: jsonEncode({'stored': stored, 'salt': salt}),
      );
      if (response.statusCode == 200) {
        return response.body;
      }
    } catch (e) {
      log("Error decrypting password: $e", isError: true);
    }
    return null;
  }

  static Future<String?> generateSalt() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/nadeko/generate-salt'),
        headers: {'X-API-Key': SettingsManager.serverApiKey.value},
      );
      if (response.statusCode == 200) {
        return response.body;
      }
    } catch (e) {
      log("Error generating salt: $e", isError: true);
    }
    return null;
  }

  static Future<Map<String, String>?> getDepsVersion() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/nadeko/deps-version'),
        headers: {'X-API-Key': SettingsManager.serverApiKey.value},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'ytdlp': data['ytdlp'] as String,
          'ffmpeg': data['ffmpeg'] as String,
        };
      }
    } catch (e) {
      log("Error getting deps version: $e", isError: true);
    }
    return null;
  }

  static void dispose() {
    _timer?.cancel();
    SettingsManager.serverHost.removeListener(restartPolling);
    SettingsManager.serverPort.removeListener(restartPolling);
    SettingsManager.serverApiKey.removeListener(restartPolling);
  }
}
