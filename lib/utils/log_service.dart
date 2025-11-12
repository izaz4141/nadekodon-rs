import 'dart:async';
import 'package:intl/intl.dart';

import 'log_entry.dart';

class LogService {
  static final List<LogEntry> logs = [];

  static void recordLog(String line) {
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
    } else {
      // If the log doesn't match the format, treat it as STDOUT
      logs.add(LogEntry(level: LogLevel.stdout, timestamp: DateTime.now(), message: line));
    }
  }

  static void clearLogs() {
    logs.clear();
  }
}