import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:rinf/rinf.dart';
import 'src/bindings/bindings.dart';

import 'app.dart';
import 'utils/notification_service.dart';
import 'utils/log_service.dart';
import 'utils/settings.dart';
import 'utils/logger.dart';

import 'utils/updater.dart';
import 'utils/ws_status_service.dart';
import 'utils/single_instance.dart';
import 'utils/app_lifecycle.dart';

final _windowListener = _WindowListener();

Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      await LogService.init();
      await SettingsManager.init();

      await cleanupOldFiles();

      await initializeRust(assignRustSignal);
      initRustSignalLogger();

      await SettingsManager.sendAllSettings();
      final torrentPath = await SettingsManager.getTorrentPersistencePath();
      InitTorrentPersistence(path: torrentPath).sendSignalToRust();
      final dbPath = await SettingsManager.getDatabasePath();
      InitDatabase(path: dbPath).sendSignalToRust();

      NotificationService().startListening();
      if (Platform.isAndroid) {
        // Permissions are now handled in App.dart via PermissionHelper
      } else {
        await SingleInstance.init(() async {
          await windowManager.show();
          await windowManager.restore();
          await windowManager.focus();
        });
        StartServer(
          port: SettingsManager.serverPort.value,
          apiKey: SettingsManager.serverApiKey.value,
        ).sendSignalToRust();
        WebsocketStatusService.init();
        await windowManager.ensureInitialized();
        await windowManager.setPreventClose(true);
        const windowOptions = WindowOptions(
          size: Size(800, 600),
          center: true,
          // skipTaskbar: false,
          titleBarStyle: TitleBarStyle.hidden,
          windowButtonVisibility: false,
        );

        if (SettingsManager.retreatToTray.value) {
          await initTray();
        }

        SettingsManager.retreatToTray.addListener(() async {
          if (SettingsManager.retreatToTray.value) {
            await initTray();
          } else {
            await removeTray();
          }
        });

        windowManager.addListener(_windowListener);
        windowManager.waitUntilReadyToShow(windowOptions, () async {
          await windowManager.show();
          await windowManager.focus();
        });
      }

      runApp(const NadekoDon());
    },
    (error, stack) {
      log('Error: $error', isError: true);
      log('Stack: $stack', isError: true);
    },
    zoneSpecification: ZoneSpecification(
      print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
        LogService.recordLog(line);
        parent.print(zone, line);
      },
    ),
  );
}

class _WindowListener extends WindowListener {
  @override
  void onWindowClose() async {
    if (SettingsManager.retreatToTray.value) {
      await windowManager.hide();
    } else {
      await closeApp();
    }
  }
}
