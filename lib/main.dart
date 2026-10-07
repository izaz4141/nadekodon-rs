import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nadekodon/ui/app.dart';
import 'package:nadekodon/utils/app_lifecycle.dart';
import 'package:nadekodon/utils/bridge_service.dart';
import 'package:nadekodon/utils/cli_args.dart';
import 'package:nadekodon/utils/file_association_service.dart';
import 'package:nadekodon/utils/helper.dart';
import 'package:nadekodon/utils/io_service.dart';
import 'package:nadekodon/utils/log_service.dart';
import 'package:nadekodon/utils/logger.dart';
import 'package:nadekodon/utils/notification_service.dart';
import 'package:nadekodon/utils/platform_service.dart';
import 'package:nadekodon/utils/rinf_service/rinf_service.dart';
import 'package:nadekodon/utils/settings.dart';
import 'package:nadekodon/utils/single_instance.dart';
import 'package:nadekodon/utils/system_service.dart';
import 'package:nadekodon/utils/updater.dart';
import 'package:rinf/rinf.dart';
import 'package:window_manager/window_manager.dart';

final _windowListener = _WindowListener();

/// [args] is the command line the engine handed us. The Flutter engine never
/// populates `Platform.executableArguments`, so this is the only way to see
/// what the process was launched with.
Future<void> main(List<String> args) async {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      LicenseRegistry.addLicense(() async* {
        final licenseText = await rootBundle.loadString(
          'assets/licenses/AGPLv3-LICENSE',
        );
        yield LicenseEntryWithLineBreaks(['Nadeko~don'], licenseText);
      });

      String? startupTarget;

      if (!kIsWeb) {
        await LogService.init();
        await initializeRust(assignRustSignal);
        initRustSignalLogger();

        // Cli args handler
        final io = IOServiceFactory.create();
        final action = await parseCliArgs(args, io);
        await action.run();

        if (action is OpenTarget) startupTarget = action.target;
      }

      if (PlatformService.isDesktop) {
        await SingleInstance.init(
          onFocus: () async {
            await PlatformService().focusWindow();
          },
          onOpen: (target) async {
            OpenTargetService.instance.deliver(target);
          },
          startupTarget: startupTarget,
        );
        OpenTargetService.instance.setStartupTarget(startupTarget);
      }

      await BridgeService.init();
      await SettingsManager.init();
      await SystemService().init();

      if (!kIsWeb) {
        await cleanupOldFiles();
        await _registerFileAssociation();
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
          masterKey: masterKey!,
          configPath: SettingsManager.configPath,
        ).sendSignalToRust();
      }

      if (PlatformService.isDesktop) {
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

/// Offers this build to Windows in the "Open with" list, if it is not already.
Future<void> _registerFileAssociation() async {
  if (!PlatformService.isWindows) return;
  try {
    final service = FileAssociationServiceFactory.create();
    if (service.isRegistered()) return;
    await service.register();
  } catch (e) {
    log('Could not register the file association: $e', isError: true);
  }
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
