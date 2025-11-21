import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:file_share_intent/file_share_intent.dart';

import 'theme/app_theme.dart';
import 'ui/pages/home_page.dart';
import 'ui/widgets/dialog/add_download.dart';
import 'utils/helper.dart';

import 'package:rinf/rinf.dart';

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
      // Handle initial intent when app is opened via sharing
      _handleInitialIntent();

      // Listen for intents while app is running
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
  }

  Future<void> _handleInitialIntent() async {
    try {
      final List<SharedMediaFile> initialMedia = await FileShareIntent.instance
          .getInitialMedia();
      if (initialMedia.isNotEmpty) {
        // Small delay to ensure context is ready
        Future.delayed(const Duration(milliseconds: 500), () {
          _handleSharedMedia(initialMedia);
        });
      }
    } catch (e) {
      // Silently handle errors
    }
  }

  void _handleSharedMedia(List<SharedMediaFile> sharedMedia) {
    // Filter for text or URL types
    final urlOrText = sharedMedia.firstWhere(
      (file) =>
          file.type == SharedMediaType.url || file.type == SharedMediaType.text,
      orElse: () => SharedMediaFile(path: '', type: SharedMediaType.file),
    );

    if (urlOrText.path.isEmpty) return;

    final sharedText = urlOrText.path;

    // Validate that the shared text is a URL
    if (!isUrl(sharedText)) {
      return;
    }

    // Get the navigator context and open the dialog
    final context = navigatorKey.currentContext;
    if (context != null) {
      showAddDownloadDialog(context, initialUrl: sharedText);
    }
  }

  @override
  void dispose() {
    _listener.dispose();
    _intentStreamSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final schemes = AppTheme.getColorSchemes(lightDynamic, darkDynamic);

        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'Nadeko~don',
          theme: AppTheme.buildTheme(schemes.light, context),
          darkTheme: AppTheme.buildTheme(schemes.dark, context),
          home: const HomePage(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}
