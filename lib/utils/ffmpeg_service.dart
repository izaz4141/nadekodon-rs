import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:nadekodon/utils/logger.dart';
import 'package:nadekodon/src/bindings/bindings.dart';

class FfmpegService {
  static void startListening() {
    RequestFfmpeg.rustSignalStream.listen((signal) async {
      final request = signal.message;
      final id = request.id;
      final args = request.args;

      log('Received FFmpeg request $id with args: $args');

      try {
        // FFmpegKit expects List<String> for arguments
        final session = await FFmpegKit.executeWithArguments(args);
        final returnCode = await session.getReturnCode();
        final logs = await session.getAllLogsAsString();
        final success = returnCode != null && returnCode.isValueSuccess();

        if (!success) {
          log('FFmpeg request $id failed: $logs', isError: true);
        }

        FfmpegResult(
          id: id,
          success: success,
          log: logs ?? '',
        ).sendSignalToRust();
      } catch (e) {
        log('Error executing FFmpeg request $id: $e', isError: true);
        FfmpegResult(
          id: id,
          success: false,
          log: e.toString(),
        ).sendSignalToRust();
      }
    });
  }
}
