import 'package:intl/intl.dart';
import 'package:nadekodon/src/bindings/bindings.dart';

void log(String message, {bool isError = false}) {
  final level = isError ? 'ERROR' : 'DEBUG';
  final timestamp = DateFormat('yy/MM/dd|HH:mm:ss').format(DateTime.now());
  final logMessage = '[$level][$timestamp] $message';
  print(logMessage);
}

void initRustSignalLogger() {
  LogSignal.rustSignalStream.listen((signalPack) {
    final isError = signalPack.message.level == "ERROR";
    log(signalPack.message.message, isError: isError);
  });
}
