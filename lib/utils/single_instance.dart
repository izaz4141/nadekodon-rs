import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class SingleInstance {
  static const String _lockFileName = '.instance_lock';
  static const String _focusCommand = 'focus';
  static File? _lockFile;

  /// Initializes the single instance mechanism.
  ///
  /// If another instance is already running, this method will signal it to focus
  /// and then exit the current process.
  ///
  /// If this is the main instance, it will start listening for signals from
  /// subsequent instances.
  ///
  /// [onFocus] is the callback to execute when a focus signal is received.
  static Future<void> init(Function onFocus) async {
    final appDocDir = await getApplicationSupportDirectory();
    _lockFile = File('${appDocDir.path}/$_lockFileName');

    bool isMainInstance = false;

    if (await _lockFile!.exists()) {
      try {
        final port = int.parse(await _lockFile!.readAsString());
        final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
        socket.write(_focusCommand);
        await socket.flush();
        await socket.close();
        exit(0);
      } catch (e) {
        // Connection failed, likely a stale lock file.
        // We will take over as the main instance.
        isMainInstance = true;
      }
    } else {
      isMainInstance = true;
    }

    if (isMainInstance) {
      await _becomeMainInstance(onFocus);
    }
  }

  static Future<void> _becomeMainInstance(Function onFocus) async {
    // Bind to an ephemeral port (port 0)
    final serverSocket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );

    // Write the assigned port to the lock file
    await _lockFile!.writeAsString(serverSocket.port.toString(), flush: true);

    // Listen for incoming connections
    serverSocket.listen((socket) {
      socket.listen((data) {
        final message = utf8.decode(data);
        if (message.trim() == _focusCommand) {
          onFocus();
        }
      });
    });
  }

  static Future<void> dispose() async {
    if (_lockFile != null) {
      try {
        if (await _lockFile!.exists()) {
          await _lockFile!.delete();
        }
      } catch (e) {
        // Ignore errors during disposal
      }
    }
  }
}
