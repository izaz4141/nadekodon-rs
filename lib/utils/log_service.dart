import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

class LogService {
  static final List<LogEntry> logs = [];
  static File? _logFile;

  static Future<void> init() async {
    final directory = await getApplicationSupportDirectory();
    _logFile = File('${directory.path}/error.log');

    if (await _logFile!.exists()) {
      final lines = await _logFile!.readAsLines();
      for (final line in lines) {
        recordLog(line, saveToFile: false);
      }
    }
  }

  static void recordLog(String line, {bool saveToFile = true}) {
    final regex = RegExp(r'\[(DEBUG|ERROR|STDOUT)\]\[(.*?)\] (.*)');
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

      logs.add(LogEntry(level: level, timestamp: timestamp, message: message!));

      if (saveToFile && level == LogLevel.error && _logFile != null) {
        _saveErrorLog(line);
      }
    } else {
      // If the log doesn't match the format, treat it as STDOUT
      logs.add(
        LogEntry(
          level: LogLevel.stdout,
          timestamp: DateTime.now(),
          message: line,
        ),
      );
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
      logs.add(
        LogEntry(
          level: LogLevel.error,
          timestamp: DateTime.now(),
          message: 'Failed to save log: $e',
        ),
      );
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
      logs.clear();
    } catch (e) {
      logs.add(
        LogEntry(
          level: LogLevel.error,
          timestamp: DateTime.now(),
          message: 'Failed to clear log: $e',
        ),
      );
    }
  }
}

enum LogLevel { debug, error, stdout }

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
