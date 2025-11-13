import 'dart:io';
import 'package:collection/collection.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:nadekodon/utils/logger.dart';

String formatBytes(int bytes) {
  const suffixes = ["B", "KB", "MB", "GB"];
  double size = bytes.toDouble();
  int i = 0;
  while (size >= 1024 && i < suffixes.length - 1) {
    size /= 1024;
    i++;
  }
  return "${size.toStringAsFixed(1)} ${suffixes[i]}";
}

String snakeToCamel(String input) {
  return input.split('_').mapIndexed((i, word) {
    if (i == 0) return word;
    return word[0].toUpperCase() + word.substring(1);
  }).join();
}

String camelToSnake(String input) {
  return input
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match[1]}_${match[2]!.toLowerCase()}',
      )
      .toLowerCase();
}

bool isUrl(String url) {
  final regex = RegExp(
    r'^(?:http|https)://'
    r'(?:(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\.)+[A-Z]{2,6}\.?|'
    r'localhost|'
    r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})'
    r'(?::\d+)?'
    r'(?:/?|[/?]\S+)$',
    caseSensitive: false,
  );
  return regex.hasMatch(url);
}

Future<bool> fileExist(String path) async {
  final file = File(path);
  return await file.exists();
}

Future<String> prepareYtDlpExecutable() async {
  try {
    if (!Platform.isAndroid) {
      return 'yt-dlp';
    }

    final supportDir = await getApplicationSupportDirectory();
    final ytDlpPath = p.join(supportDir.path, 'yt-dlp');
    final ytDlpFile = File(ytDlpPath);

    if (await ytDlpFile.exists() && await ytDlpFile.length() > 0) {
      return ytDlpPath;
    }

    ByteData bytes;
    try {
      bytes = await rootBundle.load('assets/bin/yt-dlp');
    } on FlutterError catch (e) {
      return 'yt-dlp';
    }

    await ytDlpFile.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    await Process.run('chmod', ['+x', ytDlpPath]);

    return ytDlpPath;
  } catch (e, st) {
    return 'yt-dlp';
  }
}
