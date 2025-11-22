import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

Future<void> checkAndRequestStoragePermission() async {
  if (!Platform.isAndroid) return;

  // This permission grants "All files access".
  if (await Permission.manageExternalStorage.status.isDenied) {
    await Permission.manageExternalStorage.request();
  }

  if (await Permission.storage.status.isDenied) {
    await Permission.storage.request();
  }

  if (await Permission.notification.status.isDenied) {
    await Permission.notification.request();
  }
}
