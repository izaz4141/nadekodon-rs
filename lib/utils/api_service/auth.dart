import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:nadekodon/models/account.dart';
import 'package:nadekodon/utils/helper.dart';
import 'package:nadekodon/utils/io_service.dart';
import 'package:nadekodon/utils/logger.dart';
import 'package:nadekodon/utils/rinf_service/signal_helper.dart';
import 'package:nadekodon/utils/settings.dart';

import 'http_client.dart';

mixin AuthHttpApi {
  Future<bool> login({
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

      final response = await HttpTransport.post(
        '/api/nadeko/auth/login',
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

  Future<String?> testLogin({
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

  Future<bool> regenerateApiKey() async {
    try {
      final response = await HttpTransport.get('/api/nadeko/auth/generate-api');
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

  Future<String?> hashPassword(String plainText) async {
    try {
      final response = await HttpTransport.post(
        '/api/nadeko/auth/hash',
        body: {'id': newSignalId(), 'plain_text': plainText},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['hashed_text'] as String?;
      }
    } catch (e) {
      log("Error hashing password: $e", isError: true);
    }
    return null;
  }

  Future<bool> changeCredentials({
    required String currentPassword,
    String? newUsername,
    String? newPassword,
    int? serverPort,
  }) async {
    try {
      final response = await HttpTransport.post(
        '/api/nadeko/auth/change-credentials',
        headers: {'X-Password': currentPassword},
        body: {
          'new_username': ?newUsername,
          'new_password': ?newPassword,
          'server_port': ?serverPort,
        },
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

  Future<bool> verifyPassword(String password) async {
    try {
      final response = await HttpTransport.post(
        '/api/nadeko/auth/verify-password',
        headers: {'X-Password': password},
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

  Future<String?> encrypt(String plainText) async {
    try {
      final response = await HttpTransport.post(
        '/api/nadeko/auth/encrypt',
        body: {'id': newSignalId(), 'plain_key': plainText},
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

  Future<String?> decrypt(String encryptedText) async {
    try {
      final response = await HttpTransport.post(
        '/api/nadeko/auth/decrypt',
        body: {'id': newSignalId(), 'encrypted_key': encryptedText},
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
}
