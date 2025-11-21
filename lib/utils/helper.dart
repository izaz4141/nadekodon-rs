import 'dart:io';
import 'package:collection/collection.dart';
import 'package:open_filex/open_filex.dart';

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

  final result = await OpenFilex.open(filePath);
  return result.type;
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
    } else {
      final directory = file.parent.path;
      final result = await OpenFilex.open(directory);
      return result.type == ResultType.done;
    }
  } catch (e) {
    return false;
  }
}
