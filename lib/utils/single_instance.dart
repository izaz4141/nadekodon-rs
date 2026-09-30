import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import 'package:nadekodon/utils/logger.dart';

class SingleInstance {
  static const String _lockFileName = '.instance_lock';
  static const String _focusCommand = 'focus';
  static const String _openCommand = 'open';
  static const String _separator = '\n';
  static File? _lockFile;

  /// Initializes the single instance mechanism.
  ///
  /// If another instance is already running, the relevant command is forwarded
  /// to it and this process exits. Otherwise this process becomes the main
  /// instance and starts listening for commands.
  ///
  /// [onFocus] runs when a focus signal arrives with no target to open.
  /// [onOpen] runs when another instance hands over something to open.
  ///
  /// [startupTarget] is what this process was launched with, or `null`. Only
  /// meaningful on the main instance, since a second instance exits before
  /// reaching the caller.
  static Future<void> init({
    required Future<void> Function() onFocus,
    required Future<void> Function(String target) onOpen,
    String? startupTarget,
  }) async {
    final appDocDir = await getApplicationSupportDirectory();
    _lockFile = File('${appDocDir.path}/$_lockFileName');

    bool isMainInstance = false;

    if (await _lockFile!.exists()) {
      try {
        final port = int.parse(await _lockFile!.readAsString());
        final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
        socket.write(
          startupTarget != null
              ? '$_openCommand$_separator$startupTarget'
              : _focusCommand,
        );
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
      await _becomeMainInstance(onFocus, onOpen);
    }
  }

  static Future<void> _becomeMainInstance(
    Future<void> Function() onFocus,
    Future<void> Function(String target) onOpen,
  ) async {
    // Bind to an ephemeral port (port 0)
    final serverSocket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );

    // Write the assigned port to the lock file
    await _lockFile!.writeAsString(serverSocket.port.toString(), flush: true);

    // Listen for incoming connections
    serverSocket.listen((socket) {
      // A read is not a message: a target can straddle packets, so the chunks
      // are collected until the sender closes.
      final chunks = <int>[];
      socket.listen(
        chunks.addAll,
        onDone: () => _handleMessage(utf8.decode(chunks), onFocus, onOpen),
        onError: (Object e) => log('Single instance socket failed: $e'),
      );
    });
  }

  static void _handleMessage(
    String raw,
    Future<void> Function() onFocus,
    Future<void> Function(String target) onOpen,
  ) {
    final parts = raw.split(_separator);
    switch (parts.first.trim()) {
      case _focusCommand:
        onFocus();
        return;
      case _openCommand:
        if (parts.length > 1) {
          // Never trimmed: spaces and newlines are legal in a path.
          final target = parts.sublist(1).join(_separator);
          if (target.isNotEmpty) {
            onOpen(target);
          }
        }
    }
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
