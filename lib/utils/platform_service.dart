import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'package:file_share_intent/file_share_intent.dart';
import 'package:app_links/app_links.dart';
import 'package:nadekodon/utils/logger.dart';

class PlatformService {
  static final PlatformService _instance = PlatformService._internal();
  factory PlatformService() => _instance;
  PlatformService._internal();

  StreamSubscription? _intentStreamSubscription;
  StreamSubscription? _linkSubscription;

  void init({
    required Function(String url) onUrlReceived,
    required Function(List<SharedMediaFile> media) onMediaReceived,
  }) {
    if (kIsWeb) return;

    if (Platform.isAndroid) {
      _initAppLinks(onUrlReceived);
      _initFileShareIntent(onMediaReceived);
    }
  }

  void dispose() {
    _intentStreamSubscription?.cancel();
    _linkSubscription?.cancel();
  }

  Future<void> focusWindow() async {
    if (kIsWeb ||
        (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS)) {
      return;
    }

    try {
      await windowManager.show();
      await windowManager.restore();
      await windowManager.focus();
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setAlwaysOnTop(false);
    } catch (e) {
      log('Failed to focus window: $e', isError: true);
    }
  }

  Future<void> initWindow({
    required WindowListener listener,
    required VoidCallback onReady,
  }) async {
    if (kIsWeb || !isDesktop) return;

    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    const windowOptions = WindowOptions(
      size: Size(975, 570),
      center: true,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );

    windowManager.addListener(listener);
    windowManager.waitUntilReadyToShow(windowOptions, onReady);
  }

  Future<void> startDragging() async {
    if (kIsWeb || !isDesktop) return;
    await windowManager.startDragging();
  }

  Future<bool> isMaximized() async {
    if (kIsWeb || !isDesktop) return false;
    return await windowManager.isMaximized();
  }

  Future<void> maximize() async {
    if (kIsWeb || !isDesktop) return;
    await windowManager.maximize();
  }

  Future<void> unmaximize() async {
    if (kIsWeb || !isDesktop) return;
    await windowManager.unmaximize();
  }

  void _initFileShareIntent(
    Function(List<SharedMediaFile> media) onMediaReceived,
  ) {
    try {
      FileShareIntent.instance.getInitialMedia().then((value) {
        if (value.isNotEmpty) {
          onMediaReceived(value);
        }
        FileShareIntent.instance.reset();
      });

      _intentStreamSubscription = FileShareIntent.instance
          .getMediaStream()
          .listen(
            onMediaReceived,
            onError: (err) => log('Intent error: $err', isError: true),
          );
    } catch (e) {
      log('Failed to init FileShareIntent: $e', isError: true);
    }
  }

  void _initAppLinks(Function(String url) onUrlReceived) {
    final appLinks = AppLinks();
    _linkSubscription = appLinks.uriLinkStream.listen((uri) {
      onUrlReceived(uri.toString());
    });
  }

  Future<void> hideWindow() async {
    if (kIsWeb || !isDesktop) return;
    await windowManager.hide();
  }

  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);
  static bool get isMobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  static bool get isLinux =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;
  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  static bool get isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
}
