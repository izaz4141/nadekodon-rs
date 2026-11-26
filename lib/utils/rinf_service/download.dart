import 'dart:async';

import 'package:nadekodon/src/bindings/bindings.dart';

import 'signal_helper.dart';

/// Native (rinf FFI) download operations against the embedded hub.
mixin DownloadRinfApi {
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
    final requestId = id ?? newSignalId();
    return awaitRustPush<DownloadList>(
      DownloadList.rustSignalStream,
      matches: (m) => m.id == requestId,
      send: () => GetDownloadListRequest(
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
      ).sendSignalToRust(),
    );
  }

  /// Native subscriptions keep using the rinf request/response signal pair.
  ///
  /// There is no HTTP rate limit on this path, so a periodic request is enough
  /// to expose the same streaming API to the UI. Each poll uses a fresh request
  /// ID so a late reply from a timed-out poll cannot be mistaken for the
  /// current one; the caller-supplied [id] remains the stable stream identity.
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
  }) {
    final streamId = id ?? newSignalId();
    var cancelled = false;
    Timer? delayTimer;
    Completer<void>? delayCompleter;
    late final StreamController<DownloadList> controller;

    void cancelDelay() {
      delayTimer?.cancel();
      delayTimer = null;
      final done = delayCompleter;
      delayCompleter = null;
      if (done != null && !done.isCompleted) done.complete();
    }

    Future<void> cancellableDelay() {
      final done = Completer<void>();
      delayCompleter = done;
      delayTimer = Timer(interval, () {
        if (!done.isCompleted) done.complete();
        if (identical(delayCompleter, done)) {
          delayCompleter = null;
          delayTimer = null;
        }
      });
      return done.future;
    }

    Future<void> poll() async {
      while (!cancelled) {
        final list = await getDownloadList(
          id: newSignalId(),
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
        if (list != null) controller.add(list.copyWith(id: streamId));
        await cancellableDelay();
      }
    }

    controller = StreamController<DownloadList>(
      onListen: () => unawaited(poll()),
      onCancel: () {
        cancelled = true;
        cancelDelay();
      },
    );

    return controller.stream;
  }

  Future<DownloadDetails?> getDownloadDetails(String id) async {
    return awaitRustPush<DownloadDetails>(
      DownloadDetails.rustSignalStream,
      matches: (m) => m.id == id,
      send: () => GetDownloadDetailsRequest(id: id).sendSignalToRust(),
    );
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
    final requestId = newSignalId();
    final result = await awaitRustPush<DoDownloadResponse>(
      DoDownloadResponse.rustSignalStream,
      matches: (m) => m.id == requestId,
      send: () => DoDownloadRequest(
        id: requestId,
        url: url,
        dest: dest,
        isYtdl: isYtdl,
        videoFormat: videoFormat,
        audioFormat: audioFormat,
        cookie: cookie,
        userAgent: userAgent,
        referer: referer,
        category: category,
      ).sendSignalToRust(),
    );
    return result != null && result.success ? result.downloadIds : null;
  }

  Future<bool> pauseDownload(String id) {
    PauseDownloadRequest(id: id).sendSignalToRust();
    return Future.value(true);
  }

  Future<bool> resumeDownload(String id) {
    ResumeDownloadRequest(id: id).sendSignalToRust();
    return Future.value(true);
  }

  Future<bool> updateUrl(String id, String newUrl) {
    UpdateDownloadUrlRequest(id: id, newUrl: newUrl).sendSignalToRust();
    return Future.value(true);
  }

  Future<bool> cancelDownload(String id) {
    CancelDownloadRequest(id: id).sendSignalToRust();
    return Future.value(true);
  }

  Future<bool> deleteDownload(String id, bool deleteFile) {
    DeleteDownloadRequest(id: id, deleteFile: deleteFile).sendSignalToRust();
    return Future.value(true);
  }

  Future<List<CategoryDisplay>?> getCategories({String? id}) async {
    final requestId = id ?? newSignalId();
    final result = await awaitRustPush<CategoriesOutput>(
      CategoriesOutput.rustSignalStream,
      matches: (m) => m.id == requestId,
      send: () => GetCategoriesRequest(id: requestId).sendSignalToRust(),
    );
    return result?.categories;
  }

  Future<bool> updateCategories(List<CategoryDisplay> categories) {
    UpdateCategoriesRequest(
      id: newSignalId(),
      categories: categories,
    ).sendSignalToRust();
    return Future.value(true);
  }
}
