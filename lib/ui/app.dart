import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:file_share_intent/file_share_intent.dart';

import 'package:nadekodon/ui/theme/app_theme.dart';
import 'package:nadekodon/ui/pages/home_page.dart';
import 'package:nadekodon/ui/pages/login_page.dart';
import 'package:nadekodon/ui/widgets/dialog/add_download.dart';
import 'package:nadekodon/ui/widgets/dialog/update_url_dialog.dart';
import 'package:nadekodon/ui/widgets/dialog/permission_dialog.dart';
import 'package:nadekodon/utils/helper.dart';
import 'package:nadekodon/utils/logger.dart';
import 'package:nadekodon/utils/settings.dart';
import 'package:nadekodon/utils/platform_service.dart';

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

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onExitRequested: () async {
        if (!kIsWeb) {
          finalizeRust(); // This line shuts down the async Rust runtime.
        }
        return AppExitResponse.exit;
      },
    );

    if (PlatformService.isMobile) {
      if (SettingsManager.isFirstRun) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final context = navigatorKey.currentContext;
          if (context != null) {
            showDialog(
              context: context,
              builder: (context) => const PermissionDialog(),
            );
          }
        });
      }
    }

    PlatformService().init(
      onUrlReceived: (url) => _handleIncomingUrl(url),
      onMediaReceived: (media) => _handleSharedMedia(media),
    );

    _initExtSignals();
  }

  void _initExtSignals() {
    if (kIsWeb) return;
    RequestAddDownload.rustSignalStream.listen((signal) async {
      final message = signal.message;
      await PlatformService().focusWindow();

      if (UpdateUrlDialog.isOpen) {
        return;
      }

      final context = navigatorKey.currentContext;
      if (context != null) {
        showAddDownloadDialog(
          // ignore: use_build_context_synchronously
          context,
          initialUrl: message.url,
          cookie: message.cookie,
          userAgent: message.userAgent,
          referer: message.referer,
        );
      }
    });
  }

  void _handleIncomingUrl(String url) {
    // Small delay to ensure context is ready
    Future.delayed(const Duration(milliseconds: 500), () {
      final context = navigatorKey.currentContext;
      if (context != null) {
        // ignore: use_build_context_synchronously
        showAddDownloadDialog(context, initialUrl: url);
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
    PlatformService().dispose();
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
                  builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
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
                      home: ValueListenableBuilder<bool>(
                        valueListenable: SettingsManager.requireLogin,
                        builder: (context, requireLogin, _) {
                          return ValueListenableBuilder<bool>(
                            valueListenable: SettingsManager.isLoggedIn,
                            builder: (context, isLoggedIn, _) {
                              if (requireLogin && !isLoggedIn) {
                                return LoginPage(
                                  onLoginSuccess: () {
                                    // Login handled by page, this callback just triggers rebuild
                                  },
                                );
                              }
                              return const HomePage();
                            },
                          );
                        },
                      ),
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
