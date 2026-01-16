import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:nadekodon/src/bindings/bindings.dart';
import 'package:nadekodon/utils/api_service.dart';
import 'package:nadekodon/utils/platform_service.dart';
import 'package:nadekodon/utils/ytdlp_android.dart';

class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;

  DownloadService._internal() {
    if (!kIsWeb) {
      _signalSub = DownloadList.rustSignalStream.listen((signal) {
        _listController.add(signal.message);
      });

      // Global details listener for native
      DownloadDetails.rustSignalStream.listen((signal) {
        final details = signal.message;
        if (_detailControllers.containsKey(details.id)) {
          _detailControllers[details.id]!.add(details);
        }
      });
    }
  }

  final _listController = StreamController<DownloadList>.broadcast();
  Stream<DownloadList> get listStream => _listController.stream;

  final Map<String, StreamController<DownloadDetails>> _detailControllers = {};

  StreamSubscription? _signalSub;

  Stream<DownloadDetails> getDetailsStream(String id) {
    if (!_detailControllers.containsKey(id)) {
      _detailControllers[id] = StreamController<DownloadDetails>.broadcast();
    }
    return _detailControllers[id]!.stream;
  }

  void fetchDetails(String id) {
    if (kIsWeb) {
      APIService.getDownloadDetails(id).then((details) {
        if (details != null && _detailControllers.containsKey(id)) {
          _detailControllers[id]!.add(details);
        }
      });
    } else {
      GetDownloadDetails(id: id).sendSignalToRust();
    }
  }

  void fetchList(GetDownloadList query) {
    if (kIsWeb) {
      APIService.getDownloadList(
        anchorId: query.anchorId,
        before: query.before.toInt(),
        after: query.after.toInt(),
        statuses: query.statuses,
        tag: query.tag,
        searchQuery: query.searchQuery,
        sortBy: query.sortBy,
        ascending: query.ascending,
      ).then((list) {
        if (list != null) {
          _listController.add(list);
        }
      });
    } else {
      query.sendSignalToRust();
    }
  }

  Future<UrlQueryOutput?> queryUrl({
    required String url,
    String? cookie,
    String? userAgent,
    String? referer,
  }) async {
    if (kIsWeb) {
      return APIService.queryUrl(
        url: url,
        cookie: cookie,
        userAgent: userAgent,
        referer: referer,
      );
    } else {
      QueryUrl(
        url: url,
        cookie: cookie,
        userAgent: userAgent,
        referer: referer,
      ).sendSignalToRust();
      final signal = await UrlQueryOutput.rustSignalStream.first;
      return signal.message;
    }
  }

  Future<YtdlQueryOutput?> queryYtdl({required String url}) async {
    if (PlatformService.isAndroid) {
      return YtDlpAndroid.ytdlpExtractInfo(url);
    } else if (kIsWeb) {
      return APIService.queryYtdl(url: url);
    } else {
      QueryYtdl(url: url).sendSignalToRust();
      final signal = await YtdlQueryOutput.rustSignalStream.first;
      return signal.message;
    }
  }

  Future<void> addDownload({
    String? url,
    required String dest,
    bool isYtdl = false,
    YtdlFormat? videoFormat,
    YtdlFormat? audioFormat,
    String? cookie,
    String? userAgent,
    String? referer,
  }) async {
    if (kIsWeb) {
      await APIService.addDownload(
        url: url,
        dest: dest,
        isYtdl: isYtdl,
        videoFormat: videoFormat,
        audioFormat: audioFormat,
        cookie: cookie,
        userAgent: userAgent,
        referer: referer,
      );
    } else {
      DoDownload(
        url: url,
        dest: dest,
        isYtdl: isYtdl,
        videoFormat: videoFormat,
        audioFormat: audioFormat,
        cookie: cookie,
        userAgent: userAgent,
        referer: referer,
      ).sendSignalToRust();
    }
  }

  Future<void> pauseDownload(String id) async {
    if (kIsWeb) {
      await APIService.pauseDownload(id);
    } else {
      PauseDownload(id: id).sendSignalToRust();
    }
  }

  Future<void> resumeDownload(String id) async {
    if (kIsWeb) {
      await APIService.resumeDownload(id);
    } else {
      ResumeDownload(id: id).sendSignalToRust();
    }
  }

  Future<void> updateUrl(String id, String newUrl) async {
    if (kIsWeb) {
      await APIService.updateUrl(id, newUrl);
    } else {
      UpdateDownloadUrl(id: id, newUrl: newUrl).sendSignalToRust();
    }
  }

  Future<void> cancelDownload(String id) async {
    if (kIsWeb) {
      await APIService.cancelDownload(id);
    } else {
      CancelDownload(id: id).sendSignalToRust();
    }
  }

  Future<void> deleteDownload(String id, bool deleteFile) async {
    if (kIsWeb) {
      await APIService.deleteDownload(id, deleteFile);
    } else {
      DeleteDownload(id: id, deleteFile: deleteFile).sendSignalToRust();
    }
  }

  void dispose() {
    _signalSub?.cancel();
    _listController.close();
    for (var controller in _detailControllers.values) {
      controller.close();
    }
    _detailControllers.clear();
  }
}
