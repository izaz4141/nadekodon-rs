import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:file_share_intent/file_share_intent.dart';
import 'package:app_links/app_links.dart';
import 'package:window_manager/window_manager.dart';

import 'theme/app_theme.dart';
import 'ui/pages/home_page.dart';
import 'ui/widgets/dialog/add_download.dart';
import 'utils/helper.dart';
import 'utils/logger.dart';
import 'utils/settings.dart';

import 'package:rinf/rinf.dart';
import 'package:nadekodon/src/bindings/bindings.dart';

// Global navigator key for accessing context from intent handlers
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class NadekoDon extends StatefulWidget {
  const NadekoDon({super.key});

  @override
  State<NadekoDon> createState() => _NadekoDonState();
}

class _NadekoDonState extends State<NadekoDon> {
  /// This `AppLifecycleListener` is responsible for the
  /// graceful shutdown of the async runtime in Rust.
  /// If you don't care about
  /// properly dropping Rust objects before shutdown,
  /// creating this listener is not necessary.
  late final AppLifecycleListener _listener;
  StreamSubscription? _intentStreamSubscription;
  StreamSubscription? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onExitRequested: () async {
        finalizeRust(); // This line shuts down the async Rust runtime.
        return AppExitResponse.exit;
      },
    );

    // Only set up intent handling on Android
    if (Platform.isAndroid) {
      _initAppLinks();
      _initFileShareIntent();
    }
    _initExtSignals();
  }

  void _initExtSignals() {
    RequestAddDownload.rustSignalStream.listen((signal) async {
      final message = signal.message;
      await _focusWindow();
      final context = navigatorKey.currentContext;
      if (context != null) {
        // ignore: use_build_context_synchronously
        showAddDownloadDialog(context, initialUrl: message.url);
      }
    });
  }

  /// Brings the window to focus on desktop platforms
  Future<void> _focusWindow() async {
    // Only focus window on desktop platforms
    if (!Platform.isLinux && !Platform.isWindows && !Platform.isMacOS) {
      return;
    }

    try {
      await windowManager.show();
      await windowManager.restore();
      await windowManager.focus();
      // Temporarily set always on top to ensure window pops to front
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setAlwaysOnTop(false);
    } catch (e) {
      // Silently handle errors
    }
  }

  Future<void> _initFileShareIntent() async {
    // Handle initial intent
    try {
      FileShareIntent.instance.getInitialMedia().then((value) {
        if (value.isNotEmpty) {
          // Small delay to ensure context is ready
          Future.delayed(const Duration(milliseconds: 500), () {
            _handleSharedMedia(value);
          });
        }
        FileShareIntent.instance.reset();
      });
    } catch (e) {
      // Silently handle errors
    }

    // Listen for new intents while app is running
    _intentStreamSubscription = FileShareIntent.instance
        .getMediaStream()
        .listen(
          (List<SharedMediaFile> value) {
            if (value.isNotEmpty) {
              _handleSharedMedia(value);
            }
          },
          onError: (err) {
            // Silently handle errors
          },
        );
  }

  Future<void> _initAppLinks() async {
    final appLinks = AppLinks();

    _linkSubscription = appLinks.uriLinkStream.listen((uri) {
      _handleIncomingUri(uri);
    });
  }

  void _handleIncomingUri(Uri uri) {
    // Small delay to ensure context is ready
    Future.delayed(const Duration(milliseconds: 500), () {
      final context = navigatorKey.currentContext;
      if (context != null) {
        // ignore: use_build_context_synchronously
        showAddDownloadDialog(context, initialUrl: uri.toString());
      }
    });
  }

  Future<void> _handleSharedMedia(List<SharedMediaFile> sharedMedia) async {
    log(
      'Received ${sharedMedia.length} shared media items: ${sharedMedia.map((file) => file.toMap()).join(' | ')}',
    );

    String? sharedUrl;

    for (final file in sharedMedia) {
      if (file.type == SharedMediaType.url ||
          file.type == SharedMediaType.text) {
        if (isUrl(file.path)) {
          sharedUrl = file.path;
          break;
        }
      }
    }

    if (sharedUrl == null) return;

    // Get the navigator context and open the dialog
    final context = navigatorKey.currentContext;
    if (context != null) {
      // ignore: use_build_context_synchronously
      showAddDownloadDialog(context, initialUrl: sharedUrl);
    }
  }

  @override
  void dispose() {
    _listener.dispose();
    _intentStreamSubscription?.cancel();
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: SettingsManager.themeMode,
      builder: (context, themeMode, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: SettingsManager.useDynamicColor,
          builder: (context, useDynamicColor, _) {
            return ValueListenableBuilder<int>(
              valueListenable: SettingsManager.customColor,
              builder: (context, customColorValue, _) {
                return DynamicColorBuilder(
                  builder:
                      (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
                        final schemes = AppTheme.getColorSchemes(
                          lightDynamic,
                          darkDynamic,
                          customSeed: Color(customColorValue),
                          useDynamicColor: useDynamicColor,
                        );

                        return MaterialApp(
                          navigatorKey: navigatorKey,
                          title: 'Nadeko~don',
                          theme: AppTheme.buildTheme(schemes.light, context),
                          darkTheme: AppTheme.buildTheme(schemes.dark, context),
                          themeMode: themeMode,
                          home: const HomePage(),
                          debugShowCheckedModeBanner: false,
                        );
                      },
                );
              },
            );
          },
        );
      },
    );
  }
}
