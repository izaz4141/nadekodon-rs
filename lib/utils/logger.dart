import 'package:intl/intl.dart';
import 'package:nadekodon/utils/bridge_service.dart';

void log(String message, {bool isError = false}) {
  final level = isError ? 'ERROR' : 'DEBUG';
  final timestamp = DateFormat('yy/MM/dd|HH:mm:ss').format(DateTime.now());
  final logMessage = '[$level][$timestamp] $message';
  print(logMessage);
}

void initRustSignalLogger() {
  BridgeService.rustLogMessages.listen((m) {
    final isError = m.level == "ERROR";
    log(m.message, isError: isError);
  });
}
