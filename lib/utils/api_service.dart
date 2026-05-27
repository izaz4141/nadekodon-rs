import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import 'package:nadekodon/src/bindings/bindings.dart';
import 'package:nadekodon/utils/helper.dart';
import 'package:nadekodon/utils/io_service.dart';
import 'package:nadekodon/models/account.dart';
import 'package:nadekodon/utils/settings.dart';
import 'package:nadekodon/utils/logger.dart';
import 'package:nadekodon/utils/system_service.dart';

class APIService {
  static final ValueNotifier<bool> isOnline = ValueNotifier(false);
  static final ValueNotifier<String?> serverVersion = ValueNotifier(null);
  static Timer? _timer;
  static Timer? _debounce;

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
  }

  static String get baseUrl {
    if (kIsWeb) {
      return Uri.base.origin;
    }
    String host = SettingsManager.serverHost.value;
    if (!host.contains('://')) {
      host = 'http://$host';
    }
    final port = SettingsManager.serverPort.value;
    return '$host:$port';
  }

  static String wrapImageUrl(String externalUrl) {
    if (externalUrl.isEmpty) return externalUrl;
    if (!kIsWeb) return externalUrl;
    final encoded = Uri.encodeComponent(externalUrl);
    return '$baseUrl/api/nadeko/utils/img?url=$encoded';
  }

  static void _startPolling() {
    _timer?.cancel();

    isOnline.value = false;
    serverVersion.value = null;

    _checkStatus();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _checkStatus());
  }

  static void restartPolling() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      _startPolling();
    });
  }

  static Future<bool> login({
    required String username,
    required String password,
  }) async {
    try {
      final credentials = base64Encode(utf8.encode('$username:$password'));

      Map<String, String> requestHeaders = {
        'Authorization': 'Basic $credentials',
      };

      if (kIsWeb) {
        final String? csrfToken = IOServiceFactory.create().getCookie(
          'nadekodon_csrf',
        );
        if (csrfToken != null && csrfToken.isNotEmpty) {
          requestHeaders['X-CSRF-TOKEN'] = csrfToken;
        }
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/nadeko/auth/login'),
        headers: requestHeaders,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final returnedApiKey = data['api_key'];

        if (returnedApiKey is String && returnedApiKey.isNotEmpty) {
          SettingsManager.username.value = username;
          SettingsManager.serverApiKey.value = returnedApiKey;
          await SettingsManager.loadFromBackend();
          SettingsManager.attachAutoSave();
          return true;
        }
      } else {
        log(
          'Login failed: ${response.statusCode} ${response.body}',
          isError: true,
        );
      }
    } catch (e, stack) {
      log('Login error: $e \n$stack', isError: true);
    }

    return false;
  }

  static Future<String?> testLogin({
    required String host,
    required int port,
    required String username,
    required String password,
  }) async {
    try {
      final credentials = base64Encode(utf8.encode('$username:$password'));
      final response = await http.post(
        Uri.parse(
          '${host.contains('://') ? host : 'http://$host'}:$port/api/nadeko/auth/login',
        ),
        headers: {'Authorization': 'Basic $credentials'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final key = data['api_key'];
        if (key is String && key.isNotEmpty) {
          return key;
        }
      }
    } catch (e) {
      log('Test login error: $e', isError: true);
    }
    return null;
  }

  static Future<bool> regenerateApiKey() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/nadeko/auth/generate-api'),
        headers: {'X-API-Key': SettingsManager.serverApiKey.value},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final returnedApiKey = data['api_key'];
        await SettingsManager.loadFromBackend();

        if (returnedApiKey is String && returnedApiKey.isNotEmpty) {
          SettingsManager.serverApiKey.value = returnedApiKey;
          if (!kIsWeb) {
            final masterKey = await getMasterKey();
            final encrypted = await SettingsManager.encryptKey(
              returnedApiKey,
              masterKey,
            );
            if (encrypted != null) {
              SettingsManager.encryptedServerApiKey.value = encrypted;
              final index = SettingsManager.accounts.value.indexWhere(
                (a) =>
                    a.host == SettingsManager.serverHost.value &&
                    a.port == SettingsManager.serverPort.value &&
                    a.username == SettingsManager.username.value,
              );
              if (index != -1) {
                final currentAccount = SettingsManager.accounts.value[index];
                final updatedAccount = Account(
                  host: currentAccount.host,
                  port: currentAccount.port,
                  apiKey: returnedApiKey,
                  encryptedApiKey: encrypted,
                  username: currentAccount.username,
                  label: currentAccount.label,
                );
                SettingsManager.addAccount(updatedAccount);
              }
            }
          }
          return true;
        }
      }
      log(
        'Regen API-Key failed: ${response.statusCode} ${response.body}',
        isError: true,
      );
      return false;
    } catch (e) {
      log("Regen API-Key failed: $e", isError: true);
      return false;
    }
  }

  static Future<bool> restartServer() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/nadeko/system/restart'),
        headers: {'X-API-Key': SettingsManager.serverApiKey.value},
      );
      if (response.statusCode == 200) {
        return true;
      }
      log(
        'Server restart failed: ${response.statusCode} ${response.body}',
        isError: true,
      );
      return false;
    } catch (e) {
      log("Server restart failed: $e", isError: true);
      return false;
    }
  }

  static Future<void> _checkStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/nadeko/system/status'),
        headers: {'X-API-Key': SettingsManager.serverApiKey.value},
      );
      if (response.statusCode == 200) {
        isOnline.value = true;
        try {
          final data = jsonDecode(response.body);
          if (data is Map) {
            serverVersion.value = data['version'] as String?;
          }
        } catch (_) {
          // Fallback for non-JSON status response if any
        }
      } else {
        isOnline.value = false;
        serverVersion.value = null;
        log(
          "Server status check failed: ${response.statusCode} ${response.body}",
        );
      }
    } catch (e) {
      // Don't log typical connection refused errors as they spam when server is off
      if (!isOnline.value) {
        // suppress
      } else {
        log("Server status check failed: $e", isError: true);
      }
      isOnline.value = false;
      serverVersion.value = null;
    }
  }

  static Future<String?> getServerVersion() async {
    await _checkStatus();
    return serverVersion.value;
  }

  static Future<DownloadList?> getDownloadList({
    int offsetIndex = 0,
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
        'offset_index': offsetIndex,
        'before': before,
        'after': after,
        'statuses': statuses,
        'tag': ?tag,
        'search_query': ?searchQuery,
        'sort_by': ?sortBy,
        'ascending': ?ascending,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/api/nadeko/download/list'),
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

  static String getDownloadUrl(String id) {
    return '$baseUrl/api/nadeko/download/file/$id';
  }

  static Future<DownloadDetails?> getDownloadDetails(String id) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/nadeko/download/details/$id'),
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
    String? category,
  }) async {
    final payload = {
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
        Uri.parse('$baseUrl/api/nadeko/utils/query-url'),
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
        Uri.parse('$baseUrl/api/nadeko/utils/query-ytdl'),
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': SettingsManager.serverApiKey.value,
        },
        body: jsonEncode({'url': url}),
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

        return YtdlQueryOutput(items: parsedItems, error: data['error']);
      }
    } catch (e) {
      log("Error querying YTDL: $e", isError: true);
    }
    return YtdlQueryOutput(items: [], error: "Connection error");
  }

  static Future<bool> pauseDownload(String id) async {
    return _sendAction('download/pause', {'id': id});
  }

  static Future<bool> resumeDownload(String id) async {
    return _sendAction('download/resume', {'id': id});
  }

  static Future<bool> updateUrl(String id, String newUrl) async {
    return _sendAction('download/update-url', {'id': id, 'new_url': newUrl});
  }

  static Future<bool> cancelDownload(String id) async {
    return _sendAction('download/cancel', {'id': id});
  }

  static Future<bool> deleteDownload(String id, bool deleteFile) async {
    return _sendAction('download/delete', {
      'id': id,
      'delete_file': deleteFile,
    });
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
        Uri.parse('$baseUrl/api/nadeko/system/settings'),
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
        Uri.parse('$baseUrl/api/nadeko/system/settings'),
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

  static Future<String?> hashPassword(String plainText, String salt) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/nadeko/auth/hash'),
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
      log("Error hashing password: $e", isError: true);
    }
    return null;
  }

  static Future<String?> generateSalt() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/nadeko/auth/generate-salt'),
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

  static Future<String?> getCurrentVersion(String app) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/nadeko/version/current?app=$app'),
        headers: {'X-API-Key': SettingsManager.serverApiKey.value},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['version'] as String?;
      }
    } catch (e) {
      log("Error getting current version: $e", isError: true);
    }
    return null;
  }

  static Future<VersionInfo?> getLatestVersion(
    String owner,
    String repo, {
    bool nightly = false,
    bool atomic = true,
  }) async {
    try {
      final response = await http.get(
        Uri.parse(
          '$baseUrl/api/nadeko/version/latest?owner=$owner&repo=$repo&nightly=$nightly&atomic=$atomic',
        ),
        headers: {'X-API-Key': SettingsManager.serverApiKey.value},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['error'] != Null) {
          final version = VersionInfo.fromJson(data);
          return version;
        }
      }
    } catch (e) {
      log("Error getting latest version: $e", isError: true);
    }
    return null;
  }

  static Future<String?> compareVersions(List<String> versions) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/nadeko/version/compare'),
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': SettingsManager.serverApiKey.value,
        },
        body: jsonEncode({'versions': versions}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['latest'] as String?;
      }
    } catch (e) {
      log("Error comparing versions: $e", isError: true);
    }
    return null;
  }

  static void dispose() {
    _timer?.cancel();
    SettingsManager.serverHost.removeListener(restartPolling);
    SettingsManager.serverPort.removeListener(restartPolling);
    SettingsManager.serverApiKey.removeListener(restartPolling);
  }

  static Future<bool> changeCredentials({
    required String currentPassword,
    String? newUsername,
    String? newPassword,
    int? serverPort,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/nadeko/auth/change-credentials'),
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': SettingsManager.serverApiKey.value,
          'X-Password': currentPassword,
        },
        body: jsonEncode({
          'new_username': ?newUsername,
          'new_password': ?newPassword,
          'server_port': ?serverPort,
        }),
      );
      if (response.statusCode == 200) {
        await SettingsManager.loadFromBackend();
        return true;
      }
      log(
        'Change credentials failed: ${response.statusCode} ${response.body}',
        isError: true,
      );
    } catch (e) {
      log("Change credentials error: $e", isError: true);
    }
    return false;
  }

  static Future<bool> verifyPassword(String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/nadeko/auth/verify-password'),
        headers: {
          'X-API-Key': SettingsManager.serverApiKey.value,
          'X-Password': password,
        },
      );
      if (response.statusCode == 200) {
        return true;
      }
      log(
        'Verify password failed: ${response.statusCode} ${response.body}',
        isError: true,
      );
    } catch (e) {
      log("Verify password error: $e", isError: true);
    }
    return false;
  }

  static Future<String?> encrypt(String plainText) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/nadeko/auth/encrypt'),
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': SettingsManager.serverApiKey.value,
        },
        body: jsonEncode({'plain_key': plainText}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['encrypted_key'] as String?;
      }
    } catch (e) {
      log("Encrypt error: $e", isError: true);
    }
    return null;
  }

  static Future<String?> decrypt(String encryptedText) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/nadeko/auth/decrypt'),
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': SettingsManager.serverApiKey.value,
        },
        body: jsonEncode({'encrypted_key': encryptedText}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['decrypted_key'] as String?;
      }
    } catch (e) {
      log("Decrypt error: $e", isError: true);
    }
    return null;
  }

  static Future<List<CategoryDisplay>?> getCategories() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/nadeko/download/categories'),
        headers: {'X-API-Key': SettingsManager.serverApiKey.value},
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

  static Future<bool> updateCategories(List<CategoryDisplay> categories) async {
    try {
      final payload = {
        'categories': categories
            .map((c) => {'name': c.name, 'save_path': c.savePath})
            .toList(),
      };
      final response = await http.post(
        Uri.parse('$baseUrl/api/nadeko/download/categories'),
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': SettingsManager.serverApiKey.value,
        },
        body: jsonEncode(payload),
      );
      return response.statusCode == 200;
    } catch (e) {
      log("Update categories error: $e", isError: true);
    }
    return false;
  }
}
