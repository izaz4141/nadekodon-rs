import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

import 'package:rinf/rinf.dart';
import 'src/bindings/bindings.dart';

import 'app.dart';
import 'utils/notification_service.dart';
import 'utils/log_service.dart';
import 'utils/settings.dart';
import 'utils/logger.dart';
import 'utils/permission_helper.dart';
import 'utils/updater.dart';
import 'utils/ws_status_service.dart';

final _trayListener = _TrayListener();
final _windowListener = _WindowListener();

Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

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
      await checkAndRequestPermission();

      if (!Platform.isAndroid) {
        StartServer(
          port: SettingsManager.serverPort.value,
          apiKey: SettingsManager.serverApiKey.value,
        ).sendSignalToRust();
        WebsocketStatusService.init();
      }

      if (!Platform.isAndroid && !Platform.isIOS && !Platform.isFuchsia) {
        await windowManager.ensureInitialized();
        await windowManager.setPreventClose(true);
        const windowOptions = WindowOptions(
          center: true,
          // skipTaskbar: false,
          titleBarStyle: TitleBarStyle.hidden,
          windowButtonVisibility: false,
        );

        if (SettingsManager.retreatToTray.value) {
          await _initTray();
        }

        SettingsManager.retreatToTray.addListener(() async {
          if (SettingsManager.retreatToTray.value) {
            await _initTray();
          } else {
            await _removeTray();
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
      NotificationService().stopListening();
      await windowManager.destroy();
    }
  }
}

class _TrayListener extends TrayListener {
  @override
  void onTrayIconMouseDown() async {
    await windowManager.show();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'show') {
      await windowManager.show();
      await windowManager.focus();
    } else if (menuItem.key == 'exit') {
      NotificationService().stopListening();
      await windowManager.destroy();
    }
  }
}

Future<void> _initTray() async {
  await trayManager.setIcon('assets/icons/nadeko-don.png');
  if (!Platform.isLinux) {
    await trayManager.setToolTip(
      'Nadeko~don',
    ); // tooltip works only on supported platforms
  }
  await trayManager.setContextMenu(
    Menu(
      items: [
        MenuItem(
          key: 'show',
          label: 'Show App',
          icon: 'assets/icons/nadeko-don.png',
        ),
        MenuItem(key: 'exit', label: 'Close App'),
      ],
    ),
  );
  trayManager.addListener(_trayListener);
}

Future<void> _removeTray() async {
  trayManager.removeListener(_trayListener);
  await trayManager.destroy();
}
