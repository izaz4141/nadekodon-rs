import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

class LogService {
  static final ValueNotifier<List<LogEntry>> logs = ValueNotifier([]);
  static File? _logFile;

  static Future<void> init() async {
    final directory = await getApplicationSupportDirectory();
    _logFile = File('${directory.path}/error.log');

    if (await _logFile!.exists()) {
      final lines = await _logFile!.readAsLines();
      final regex = RegExp(r'\[(DEBUG|WARNING|ERROR|STDOUT)\]\[(.*?)\] (.*)');
      final loadedLogs = <LogEntry>[];

      for (final line in lines) {
        final match = regex.firstMatch(line);
        if (match != null) {
          final levelStr = match.group(1);
          final timestampStr = match.group(2);
          final message = match.group(3);

          LogLevel level;
          switch (levelStr) {
            case 'DEBUG':
              level = LogLevel.debug;
            case 'WARNING':
              level = LogLevel.warning;
            case 'ERROR':
              level = LogLevel.error;
            default:
              level = LogLevel.stdout;
          }

          DateTime timestamp;
          try {
            timestamp = DateFormat('yy/MM/dd|HH:mm:ss').parse(timestampStr!);
          } catch (e) {
            timestamp = DateTime.now();
          }

          loadedLogs.add(
            LogEntry(level: level, timestamp: timestamp, message: message!),
          );
        }
      }

      logs.value = loadedLogs;
    }
  }

  static void recordLog(String line, {bool saveToFile = true}) {
    final regex = RegExp(r'\[(DEBUG|WARNING|ERROR|STDOUT)\]\[(.*?)\] (.*)');
    final match = regex.firstMatch(line);

    if (match != null) {
      final levelStr = match.group(1);
      final timestampStr = match.group(2);
      final message = match.group(3);

      LogLevel level;
      switch (levelStr) {
        case 'DEBUG':
          level = LogLevel.debug;
          break;
        case 'WARNING':
          level = LogLevel.warning;
          break;
        case 'ERROR':
          level = LogLevel.error;
          break;
        default:
          level = LogLevel.stdout;
      }

      DateTime timestamp;
      try {
        timestamp = DateFormat('yy/MM/dd|HH:mm:ss').parse(timestampStr!);
      } catch (e) {
        timestamp = DateTime.now();
      }

      final newEntry = LogEntry(
        level: level,
        timestamp: timestamp,
        message: message!,
      );
      logs.value = [...logs.value, newEntry];

      if (saveToFile && level == LogLevel.error && _logFile != null) {
        _saveErrorLog(line);
      }
    } else {
      // If the log doesn't match the format, treat it as STDOUT
      final newEntry = LogEntry(
        level: LogLevel.stdout,
        timestamp: DateTime.now(),
        message: line,
      );
      logs.value = [...logs.value, newEntry];
    }
  }

  static Future<void> _saveErrorLog(String line) async {
    try {
      if (!await _logFile!.exists()) {
        await _logFile!.create();
      }

      List<String> lines = await _logFile!.readAsLines();
      while (lines.length >= 1000) {
        lines.removeAt(0); // Remove oldest
      }
      lines.add(line);
      await _logFile!.writeAsString(lines.join('\n'), flush: true);
    } catch (e) {
      final newEntry = LogEntry(
        level: LogLevel.error,
        timestamp: DateTime.now(),
        message: 'Failed to save log: $e',
      );
      logs.value = [...logs.value, newEntry];
    }
  }

  static Future<void> clearLogs() async {
    try {
      final file = _logFile;
      if (file == null) {
        throw StateError('Log file is not initialized');
      }

      if (await file.exists()) {
        await file.writeAsString('', flush: true);
      } else {
        await file.create(recursive: true);
      }
      logs.value = [];
    } catch (e) {
      final newEntry = LogEntry(
        level: LogLevel.error,
        timestamp: DateTime.now(),
        message: 'Failed to clear log: $e',
      );
      logs.value = [...logs.value, newEntry];
    }
  }
}

enum LogLevel { debug, warning, error, stdout }

class LogEntry {
  final LogLevel level;
  final DateTime timestamp;
  final String message;

  LogEntry({
    required this.level,
    required this.timestamp,
    required this.message,
  });
}
