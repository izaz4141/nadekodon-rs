import 'dart:io';
import 'package:collection/collection.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
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

Future<void> deleteDownloadFile(String filePath) async {
  final file = File(filePath);
  if (await file.exists()) {
    await file.delete();
  } else {
    throw Exception('File not found: $filePath');
  }
}

Future<ResultType> openFile(String filePath) async {
  final file = File(filePath);

  if (!await file.exists()) {
    return ResultType.fileNotFound;
  }

  try {
    final result = await OpenFilex.open(filePath);
    return result.type;
  } catch (e) {
    log('Error opening file: $e', isError: true);
    return ResultType.error;
  }
}

Future<bool> showInFolder(String filePath) async {
  final file = File(filePath);

  if (!await file.exists()) {
    return false;
  }

  try {
    if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', filePath]);
      return true;
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', filePath]);
      return true;
    } else if (Platform.isAndroid) {
      // On Android, try multiple methods to open the directory
      final directory = file.parent.path;

      // Method 1: Try OpenFilex first
      final result = await OpenFilex.open(directory);
      if (result.type == ResultType.done) {
        return true;
      }

      // Method 2: Fallback to url_launcher with file:// URI
      try {
        final uri = Uri.file(directory);
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) {
          return true;
        }
      } catch (e) {
        log('Error launching directory with url_launcher: $e', isError: true);
      }

      // If both methods fail, return false
      return false;
    } else if (Platform.isLinux) {
      // On Linux, try to open with the default file manager
      final directory = file.parent.path;
      try {
        await Process.run('xdg-open', [directory]);
        return true;
      } catch (e) {
        // Fallback to OpenFilex
        final result = await OpenFilex.open(directory);
        return result.type == ResultType.done;
      }
    } else {
      // Fallback for other platforms
      final directory = file.parent.path;
      final result = await OpenFilex.open(directory);
      return result.type == ResultType.done;
    }
  } catch (e) {
    log('Error opening folder: $e', isError: true);
    return false;
  }
}
