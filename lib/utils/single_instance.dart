import 'package:nadekodon/utils/io_service.dart';

class SingleInstance {
  static const String _lockFileName = '.instance_lock';
  static const String _focusCommand = 'focus';
  static const String _openCommand = 'open';
  static const String _separator = '\n';
  static IOService? _io;
  static String? _lockFilePath;

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
    _io = IOServiceFactory.create();
    _lockFilePath = '${await _io!.getConfigDir()}/$_lockFileName';

    bool isMainInstance = false;

    if (await _io!.fileExists(_lockFilePath!)) {
      try {
        final port = int.parse(await _io!.readFile(_lockFilePath!));
        final channel = await _io!.connectLocalChannel(port);
        await channel.send(
          startupTarget != null
              ? '$_openCommand$_separator$startupTarget'
              : _focusCommand,
        );
        _io!.exit(0);
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
    final server = await _io!.bindLocalChannel();

    // The port has to be on disk before any second instance can read it.
    await _io!.writeFile(_lockFilePath!, '${server.port}', flush: true);

    server.onMessage((raw) => _handleMessage(raw, onFocus, onOpen));
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
    if (_io != null && _lockFilePath != null) {
      try {
        if (await _io!.fileExists(_lockFilePath!)) {
          await _io!.deleteFile(_lockFilePath!);
        }
      } catch (e) {
        // Ignore errors during disposal
      }
    }
  }
}
