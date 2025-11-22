import 'dart:ui';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:file_share_intent/file_share_intent.dart';
import 'package:path_provider/path_provider.dart';

import 'theme/app_theme.dart';
import 'ui/pages/home_page.dart';
import 'ui/widgets/dialog/add_download.dart';
import 'utils/helper.dart';
import 'utils/logger.dart';

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
      } else if (file.type == SharedMediaType.file) {
        try {
          final tempDir = await getTemporaryDirectory();
          File fileToRead = File(file.path);

          // If the path is not absolute or doesn't exist, try finding it in temp dir
          if (!await fileToRead.exists()) {
            // Remove leading slash if present to join correctly
            final relativePath = file.path.startsWith('/')
                ? file.path.substring(1)
                : file.path;
            fileToRead = File('${tempDir.path}/$relativePath');
          }
          if (await fileToRead.exists()) {
            final fileContent = await fileToRead.readAsString();
            final trimmedContent = fileContent.trim();
            if (isUrl(trimmedContent)) {
              sharedUrl = trimmedContent;
              break;
            }
          } else {
            log(
              'Shared file not found at ${file.path} or ${fileToRead.path}',
              isError: true,
            );
          }
        } catch (e) {
          log('Error reading shared file: $e', isError: true);
        }
      }
    }

    if (sharedUrl == null) return;

    // Get the navigator context and open the dialog
    final context = navigatorKey.currentContext;
    if (context != null) {
      showAddDownloadDialog(context, initialUrl: sharedUrl);
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
