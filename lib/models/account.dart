import 'package:nadekodon/utils/settings.dart';
import 'package:nadekodon/utils/helper.dart';

class Account {
  final String host;
  final int port;
  final String apiKey;
  final String encryptedApiKey;
  final String username;
  final String label;

  Account({
    required this.host,
    required this.port,
    required this.apiKey,
    required this.encryptedApiKey,
    required this.username,
    String? label,
  }) : label = label ?? host;

  static Future<Account> fromJson(Map<String, dynamic> json) async {
    final apiKey = json['api_key'] ?? '';
    final masterKey = await getMasterKey();

    if (masterKey == null || apiKey.isEmpty) {
      return Account(
        host: json['host'] ?? '127.0.0.1',
        port: json['port'] ?? 8080,
        apiKey: apiKey,
        encryptedApiKey: apiKey,
        username: json['username'] ?? 'admin',
        label: json['label'],
      );
    }

    if (apiKey.startsWith('NDK:')) {
      return Account(
        host: json['host'] ?? '127.0.0.1',
        port: json['port'] ?? 8080,
        apiKey: apiKey,
        encryptedApiKey: apiKey,
        username: json['username'] ?? 'admin',
        label: json['label'],
      );
    } else {
      final encrypted = await SettingsManager.encryptKey(apiKey, masterKey);
      return Account(
        host: json['host'] ?? '127.0.0.1',
        port: json['port'] ?? 8080,
        apiKey: apiKey,
        encryptedApiKey: encrypted ?? apiKey,
        username: json['username'] ?? 'admin',
        label: json['label'],
      );
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'port': port,
      'api_key': encryptedApiKey,
      'username': username,
      'label': label,
    };
  }
}
