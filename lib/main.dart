import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

import 'package:rinf/rinf.dart';
import 'src/bindings/bindings.dart';

import 'app.dart';
import 'utils/settings.dart';

final _trayListener = _TrayListener();
final _windowListener = _WindowListener();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SettingsManager.init();

  await initializeRust(assignRustSignal);
  await SettingsManager.sendAllSettings();

  if (!Platform.isAndroid) {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    const windowOptions = WindowOptions(
      center: true,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      // windowButtonVisibility: false,
    );

    if (SettingsManager.retreatToTray.value) {
      await trayManager.setIcon('assets/nadeko-don.png');
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
              icon: 'assets/nadeko-don.png',
            ),
            MenuItem(key: 'exit', label: 'Close App'),
          ],
        ),
      );
    }
    trayManager.addListener(_trayListener);

    windowManager.addListener(_windowListener);
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const NadekoDon());
}

class _WindowListener extends WindowListener {
  @override
  void onWindowClose() async {
    if (SettingsManager.retreatToTray.value) {
      await windowManager.hide();
    } else {
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
      await windowManager.destroy();
    }
  }
}
