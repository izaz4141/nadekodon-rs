import 'package:rinf/rinf.dart';

import 'package:nadekodon/src/bindings/bindings.dart';
import 'package:nadekodon/utils/bridge/contract.dart';

import 'auth.dart' show rinfEncryptKey, rinfDecryptKey;
import 'signal_helper.dart';
import 'tagging.dart' as tagging;

/// Native (rinf FFI) runtime bootstrap/teardown, rust-log forwarding, settings
/// push, and master-key obfuscation ([`x0`]/[`d0`], [`encryptKey`]/[`decryptKey`]).
mixin NativeRinfApi implements ApiServiceContract {
  @override
  Future<void> initNativeRuntime() async => initializeRust(assignRustSignal);

  @override
  void shutdownNative() => finalizeRust();

  @override
  Stream<({String level, String message})> get rustLogMessages =>
      LogSignal.rustSignalStream.map(
        (pack) => (level: pack.message.level, message: pack.message.message),
      );

  @override
  Future<void> updateSettings({
    String? downloadDir,
    int? speedLimit,
    int? downloadThreads,
    int? concurrencyLimit,
    int? downloadTimeout,
    int? downloadRetries,
    double? seedingRatio,
    int? seedingTime,
    int? stalledTime,
  }) async {
    UpdateSettingsRequest(
      id: newSignalId(),
      downloadDir: downloadDir,
      speedLimit: speedLimit == null
          ? null
          : Uint64.fromBigInt(BigInt.from(speedLimit)),
      downloadThreads: downloadThreads,
      concurrencyLimit: concurrencyLimit,
      downloadTimeout: downloadTimeout == null
          ? null
          : Uint64.fromBigInt(BigInt.from(downloadTimeout)),
      downloadRetries: downloadRetries,
      seedingRatio: seedingRatio,
      seedingTime: seedingTime == null
          ? null
          : Uint64.fromBigInt(BigInt.from(seedingTime)),
      stalledTime: stalledTime == null
          ? null
          : Uint64.fromBigInt(BigInt.from(stalledTime)),
    ).sendSignalToRust();
  }

  @override
  Future<String> x0(String input) => tagging.x0(input);

  @override
  Future<String> d0(String input) => tagging.d0(input);

  @override
  Future<String?> encryptKey(String plainKey, String? masterKey) =>
      rinfEncryptKey(plainKey, masterKey);

  @override
  Future<String?> decryptKey(String encryptedKey, String? masterKey) =>
      rinfDecryptKey(encryptedKey, masterKey);
}
