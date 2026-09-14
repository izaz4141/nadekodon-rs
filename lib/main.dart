import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'package:rinf/rinf.dart';
import 'package:nadekodon/utils/rinf_service/rinf_service.dart';

import 'package:nadekodon/ui/app.dart';
import 'package:nadekodon/utils/notification_service.dart';
import 'package:nadekodon/utils/log_service.dart';
import 'package:nadekodon/utils/settings.dart';
import 'package:nadekodon/utils/logger.dart';
import 'package:nadekodon/utils/system_service.dart';
import 'package:nadekodon/utils/updater.dart';
import 'package:nadekodon/utils/bridge_service.dart';
import 'package:nadekodon/utils/single_instance.dart';
import 'package:nadekodon/utils/app_lifecycle.dart';
import 'package:nadekodon/utils/platform_service.dart';
import 'package:nadekodon/utils/helper.dart';

final _windowListener = _WindowListener();

Future<void> main() async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      LicenseRegistry.addLicense(() async* {
        final licenseText = await rootBundle.loadString(
          'assets/licenses/AGPLv3-LICENSE',
        );
        yield LicenseEntryWithLineBreaks(['Nadeko~don'], licenseText);
      });

      if (!kIsWeb) {
        await LogService.init();
        await initializeRust(assignRustSignal);
        initRustSignalLogger();
      }

      await BridgeService.init();
      await SettingsManager.init();
      await SystemService().init();

      if (!kIsWeb) {
        await cleanupOldFiles();
        await SettingsManager.sendAllSettings();
        final torrentPath = await SettingsManager.getTorrentPersistencePath();
        InitTorrentPersistenceRequest(
          id: newSignalId(),
          path: torrentPath,
        ).sendSignalToRust();
        final dbPath = await SettingsManager.getDatabasePath();
        InitDatabaseRequest(id: newSignalId(), path: dbPath).sendSignalToRust();
        NotificationService().startListening();
        final masterKey = await getMasterKey();
        StartServerRequest(
          id: newSignalId(),
          port: SettingsManager.serverPort.value,
          apiKey: SettingsManager.serverApiKey.value,
          masterKey: masterKey!,
          username: SettingsManager.username.value,
          password: SettingsManager.password.value,
          configPath: SettingsManager.configPath,
        ).sendSignalToRust();
      }

      if (PlatformService.isDesktop) {
        await SingleInstance.init(() async {
          await PlatformService().focusWindow();
        });
        await PlatformService().initWindow(
          listener: _windowListener,
          onReady: () async {
            await PlatformService().focusWindow();
          },
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
      if (PlatformService.isDesktop) {
        await PlatformService().hideWindow();
      }
    } else {
      await closeApp();
    }
  }
}
