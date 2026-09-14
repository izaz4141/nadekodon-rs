import 'dart:async';

import 'package:rinf/rinf.dart' show RustSignalPack;

import 'package:nadekodon/src/bindings/bindings.dart';

/// Transport-agnostic output aliases: the UI consumes these logical types
/// regardless of the underlying binding name.
typedef DownloadList = GetDownloadListResponse;
typedef DownloadDetails = GetDownloadDetailsResponse;
typedef UrlQueryOutput = QueryUrlResponse;
typedef YtdlQueryOutput = QueryYtdlResponse;
typedef CategoriesOutput = GetCategoriesResponse;

String newSignalId() => DateTime.now().microsecondsSinceEpoch.toString();

/// Sends a request to Rust and waits for the matching response signal.
///
/// Subscribes to [stream] first (Rust signal streams are broadcast and do not
/// replay) then invokes [send]. For signals that carry an `id` correlation
/// field, pass a [matches] predicate (e.g. `(m) => m.id == id`). When omitted
/// the next signal on the stream is returned.
Future<T?> awaitRustPush<T>(
  Stream<RustSignalPack<T>> stream, {
  bool Function(T message)? matches,
  void Function()? send,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final completer = Completer<RustSignalPack<T>>();
  late final StreamSubscription<RustSignalPack<T>> sub;
  sub = stream.where((pack) => matches?.call(pack.message) ?? true).listen((
    pack,
  ) {
    if (!completer.isCompleted) completer.complete(pack);
  }, onError: completer.completeError);
  send?.call();
  try {
    final pack = await completer.future.timeout(timeout);
    return pack.message;
  } catch (_) {
    return null;
  } finally {
    await sub.cancel();
  }
}
