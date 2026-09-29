import 'dart:async';

import 'package:package_info_plus/package_info_plus.dart';

import 'package:nadekodon/utils/helper.dart';
import 'package:nadekodon/utils/io_service.dart';

/// What the process was asked to do on the command line.
sealed class CliAction {
  const CliAction(this.io);

  final IOService io;

  /// Carries out the command. Returns normally if the app should keep starting;
  /// commands that print and exit never come back.
  Future<void> run() async {}
}

class ShowVersion extends CliAction {
  const ShowVersion(super.io);

  @override
  Future<void> run() async {
    final info = await PackageInfo.fromPlatform();
    io.writeLine('Nadeko~don ${info.version}+${info.buildNumber}');
    io.exit(0);
  }
}

class ShowHelp extends CliAction {
  const ShowHelp(super.io);

  @override
  Future<void> run() async {
    io.writeLine(cliUsage);
    io.exit(0);
  }
}

/// Open something the app understands: a local `.torrent` path, a `file://`
/// URI, an `http(s)` URL or a magnet link.
class OpenTarget extends CliAction {
  const OpenTarget(super.io, this.target);

  final String target;
}

class RunNormally extends CliAction {
  const RunNormally(super.io);
}

const String cliUsage = '''
Nadeko~don - a download manager.

Usage:
  nadekodon [options] [target]

target may be a .torrent file, a file:// URI, a http(s) URL or a magnet link.

Options:
  -v, --version   Print the version and exit
  -h, --help      Show this help and exit

Only one instance runs: launching again focuses the existing window, or hands
the target to it.
''';

/// Interprets the command line the OS handed to this process. Only call this
/// where a real filesystem exists, since confirming a local path goes through
/// [IOService].
Future<CliAction> parseCliArgs(List<String> args, IOService io) async {
  for (final arg in args) {
    switch (arg) {
      case '--version':
      case '-v':
        return ShowVersion(io);
      case '--help':
      case '-h':
        return ShowHelp(io);
    }
  }

  // Flags win over a target, so only look for one once none were given.
  final target = await _firstOpenTarget(args, io);
  if (target != null) {
    return OpenTarget(io, target);
  }

  return RunNormally(io);
}

Future<String?> _firstOpenTarget(List<String> args, IOService io) async {
  for (final arg in args) {
    final target = _normalizeTarget(arg);
    if (target == null) continue;
    if (!isValidDownloadInput(target)) continue;
    // Skipping a path that is not really there keeps a stale file association
    // from opening an error dialog.
    if (isLocalTorrentPath(target) && !await io.fileExists(target)) continue;
    return target;
  }
  return null;
}

/// Turns a `file://` URI into a path, leaving anything else untouched.
String? _normalizeTarget(String arg) {
  if (arg.isEmpty) return null;

  if (arg.toLowerCase().startsWith('file://')) {
    try {
      return Uri.parse(arg).toFilePath();
    } on FormatException {
      return null;
    }
  }

  return arg;
}

/// Carries open targets from the OS into the widget tree.
///
/// A forwarded target can arrive before the UI is listening, while the primary
/// process is still starting up, so buffering here is what keeps it from being
/// dropped.
class OpenTargetService {
  OpenTargetService._();

  static final instance = OpenTargetService._();

  // Deliberately not broadcast: a single subscription stream buffers events
  // until `NadekoDon` listens, which is exactly the late subscriber case.
  final _controller = StreamController<String>();

  /// A target passed on the command line at process start.
  String? _startupTarget;

  Stream<String> get targets => _controller.stream;

  void setStartupTarget(String? target) {
    _startupTarget = target;
  }

  /// Returns and clears the command line target, if any.
  String? takeStartupTarget() {
    final target = _startupTarget;
    _startupTarget = null;
    return target;
  }

  /// Records a target handed over by a second instance.
  void deliver(String target) {
    if (target.isEmpty) return;
    _controller.add(target);
  }
}
