enum LogLevel { debug, error, stdout }

class LogEntry {
  final LogLevel level;
  final DateTime timestamp;
  final String message;

  LogEntry({required this.level, required this.timestamp, required this.message});
}
