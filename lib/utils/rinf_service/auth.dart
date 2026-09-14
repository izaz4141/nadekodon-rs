import 'package:nadekodon/src/bindings/bindings.dart';
import 'package:nadekodon/utils/helper.dart';
import 'package:nadekodon/utils/io_service.dart';
import 'package:nadekodon/utils/logger.dart';
import 'package:nadekodon/utils/settings.dart';

import 'signal_helper.dart';
import 'tagging.dart';

/// Native (rinf FFI) auth operations. Operates on the embedded hub directly,
/// using the local master key for encryption/decryption.
mixin AuthRinfApi {
  Future<String?> hashPassword(String plainText) async {
    final id = newSignalId();
    final signal = await awaitRustPush<HashResponse>(
      HashResponse.rustSignalStream,
      matches: (m) => m.id == id,
      send: () => HashRequest(id: id, plainText: plainText).sendSignalToRust(),
    );
    return signal?.hashedText;
  }

  Future<bool> regenerateApiKey() async {
    try {
      final ioService = IOServiceFactory.create();
      final configDir = await ioService.getConfigDir();
      final masterKeyPath = '$configDir/${SettingsManager.masterKeyFile}';
      final masterKeyExists = await ioService.fileExists(masterKeyPath);
      String? existingMasterKey;
      if (masterKeyExists) {
        final encoded = await ioService.readFile(masterKeyPath);
        existingMasterKey = await d0(encoded);
      }

      final id = newSignalId();
      final signal = await awaitRustPush<NewApiKeyResponse>(
        NewApiKeyResponse.rustSignalStream,
        matches: (m) => m.id == id,
        send: () => NewApiKeyRequest(
          id: id,
          masterKey: existingMasterKey,
        ).sendSignalToRust(),
      );
      if (signal == null) return false;

      final encodedKey = await x0(signal.masterKey);
      await ioService.writeFile(masterKeyPath, encodedKey);
      await ioService.setPermissions(masterKeyPath, '0600');
      SettingsManager.serverApiKey.value = signal.decryptedApiKey;
      SettingsManager.encryptedServerApiKey.value = signal.encryptedApiKey;
      await SettingsManager.saveChanged(
        'server_api_key',
        signal.encryptedApiKey,
      );
      return true;
    } catch (e) {
      log("Regenerate API key error: $e", isError: true);
      return false;
    }
  }

  Future<String?> encrypt(String plainText) async {
    final masterKey = await getMasterKey();
    return rinfEncryptKey(plainText, masterKey);
  }

  Future<String?> decrypt(String encryptedText) async {
    final masterKey = await getMasterKey();
    return rinfDecryptKey(encryptedText, masterKey);
  }
}

/// Encrypts [plainKey] with [masterKey] through the native hub. Used by
/// `SettingsManager`/`Account` which manage their own master key.
Future<String?> rinfEncryptKey(String plainKey, String? masterKey) async {
  if (masterKey == null) return null;
  final id = newSignalId();
  final signal = await awaitRustPush<EncryptResponse>(
    EncryptResponse.rustSignalStream,
    matches: (m) => m.id == id,
    send: () => EncryptRequest(
      id: id,
      plainKey: plainKey,
      masterKey: masterKey,
    ).sendSignalToRust(),
  );
  final encrypted = signal?.encryptedKey;
  return (encrypted != null && encrypted.isNotEmpty) ? encrypted : null;
}

/// Decrypts [encryptedKey] with [masterKey] through the native hub.
Future<String?> rinfDecryptKey(String encryptedKey, String? masterKey) async {
  if (masterKey == null) return null;
  final id = newSignalId();
  final signal = await awaitRustPush<DecryptResponse>(
    DecryptResponse.rustSignalStream,
    matches: (m) => m.id == id,
    send: () => DecryptRequest(
      id: id,
      encryptedKey: encryptedKey,
      masterKey: masterKey,
    ).sendSignalToRust(),
  );
  final decrypted = signal?.decryptedKey;
  return (decrypted != null && decrypted.isNotEmpty) ? decrypted : null;
}
