import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:nadekodon/utils/notification_service.dart';
import 'package:nadekodon/utils/single_instance.dart';

final _trayListener = _AppTrayListener();

class _AppTrayListener extends TrayListener {
  @override
  void onTrayIconMouseDown() async {
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    if (!kIsWeb && !Platform.isLinux) {
      trayManager.popUpContextMenu();
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'show') {
      await windowManager.show();
      await windowManager.restore();
      await windowManager.focus();
    } else if (menuItem.key == 'exit') {
      await closeApp();
    }
  }
}

Future<void> initTray() async {
  if (kIsWeb) return;
  await trayManager.setIcon(
    Platform.isWindows
        ? 'assets/icons/nadeko-don.ico'
        : 'assets/icons/nadeko-don-32.png',
  );
  if (!Platform.isLinux) {
    await trayManager.setToolTip(
      'Nadeko~don',
    ); // tooltip works only on supported platforms
  }
  await trayManager.setContextMenu(
    Menu(
      items: [
        MenuItem(key: 'show', label: 'Show App'),
        MenuItem(key: 'exit', label: 'Close App'),
      ],
    ),
  );
  trayManager.addListener(_trayListener);
}

Future<void> removeTray() async {
  trayManager.removeListener(_trayListener);
  await trayManager.destroy();
}

Future<void> cleanupIntegrations() async {
  if (kIsWeb) return;
  await SingleInstance.dispose();
  NotificationService().stopListening();
  await removeTray();
}

Future<void> closeApp() async {
  if (kIsWeb) return;
  await cleanupIntegrations();
  await windowManager.destroy();
}
