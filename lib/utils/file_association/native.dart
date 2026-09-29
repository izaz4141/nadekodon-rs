import 'dart:io';

import 'package:win32_registry/win32_registry.dart';

import 'package:nadekodon/utils/logger.dart';
import 'package:nadekodon/utils/file_association/base.dart';

/// Offers the running build to Windows as a handler for `.torrent` files and
/// `magnet:` links.
///
/// Both formats go into the *Open with* list only, so a handler the user
/// already had is left alone. Nothing here writes a default value under
/// `Software\Classes\.torrent` or `Software\Classes\magnet`, and `UserChoice`
/// is hash protected anyway, so the user always picks Nadeko~don themselves.
class _FileAssociationNative implements FileAssociationService {
  static const String _description = 'Nadeko~don Torrent';
  static const String _torrentMimeType = 'application/x-bittorrent';
  static const String _torrentProgId = 'NadekoDon.Torrent';
  static const String _magnetProgId = 'NadekoDon.Magnet';

  // Spelled out rather than built by interpolation: a raw string cannot
  // interpolate, and a non-raw one needs every backslash escaped.
  static const String _torrentProgIdPath =
      r'Software\Classes\NadekoDon.Torrent';
  static const String _torrentCommandPath =
      r'Software\Classes\NadekoDon.Torrent\shell\open\command';
  static const String _torrentOpenWithPath =
      r'Software\Classes\.torrent\OpenWithProgids';
  static const String _magnetProgIdPath =
      r'Software\Classes\NadekoDon.Magnet';
  static const String _magnetCommandPath =
      r'Software\Classes\NadekoDon.Magnet\shell\open\command';
  static const String _magnetOpenWithPath =
      r'Software\Classes\magnet\OpenWithProgids';

  @override
  bool isRegistered() {
    // Everything below is FFI, so on another platform it is a hard failure
    // rather than a catchable exception.
    if (!Platform.isWindows) return false;
    final command = _command();
    try {
      return _isOffered(_torrentOpenWithPath, _torrentProgId, _torrentCommandPath, command) &&
          _isOffered(_magnetOpenWithPath, _magnetProgId, _magnetCommandPath, command);
    } catch (e) {
      log('File association lookup failed: $e', isError: true);
      return false;
    }
  }

  @override
  Future<void> register() async {
    if (!Platform.isWindows) return;
    try {
      final command = _command();
      _registerTorrent(Platform.resolvedExecutable, command);
      _registerMagnet(Platform.resolvedExecutable, command);
    } catch (e, s) {
      log('Failed to register file association: $e\n$s', isError: true);
      rethrow;
    }

    if (!isRegistered()) {
      log('File association did not take effect', isError: true);
    }
  }

  /// The command the shell runs to hand us a file or a link.
  String _command() => '"${Platform.resolvedExecutable}" "%1"';

  /// Whether [progId] is listed for the format *and* still runs this build, so
  /// a removed list entry or a moved executable both get written again.
  bool _isOffered(String listPath, String progId, String commandPath, String command) {
    return _readValue(listPath, progId) == '' && _readDefault(commandPath) == command;
  }

  String? _readDefault(String path) => _readValue(path, '');

  String? _readValue(String path, String name) {
    final key = CURRENT_USER.open(
      path,
      config: const RegistryOpenConfig(access: RegistryAccess.read),
    );
    try {
      return (key.getValue(name) as StringValue?)?.value;
    } finally {
      key.close();
    }
  }

  // `create` is not implied by calling `create()`: supplying a config drops
  // that method's own default, and a config without it opens rather than
  // creates, which fails on the first run when the key does not exist yet.
  RegistryKey _create(String path) => CURRENT_USER.create(
    path,
    config: const RegistryOpenConfig(
      access: RegistryAccess.readWrite,
      create: true,
    ),
  );

  void _write(String path, Map<String, RegistryValue> values) {
    final key = _create(path);
    try {
      for (final entry in values.entries) {
        key.setValue(entry.key, entry.value);
      }
    } finally {
      key.close();
    }
  }

  void _registerTorrent(String exe, String command) {
    _write(_torrentProgIdPath, {
      // The empty name is the key's default value.
      '': const StringValue(_description),
      'FriendlyTypeName': const StringValue(_description),
      'Content Type': const StringValue(_torrentMimeType),
      'Icon': StringValue('$exe,0'),
    });

    _write(_torrentCommandPath, {'': StringValue(command)});

    // An empty value is how Windows records "this ProgId can open this type".
    _write(_torrentOpenWithPath, {_torrentProgId: const StringValue('')});
  }

  /// Registers through a ProgId of our own, so `Software\Classes\magnet` only
  /// gains an `OpenWithProgids` entry and keeps whatever default it had.
  void _registerMagnet(String exe, String command) {
    _write(_magnetProgIdPath, {
      '': const StringValue(_description),
      'FriendlyTypeName': const StringValue(_description),
      // The empty value is what marks a ProgId as a protocol handler.
      'URL Protocol': const StringValue(''),
      'Icon': StringValue('$exe,0'),
    });

    _write(_magnetCommandPath, {'': StringValue(command)});
    _write(_magnetOpenWithPath, {_magnetProgId: const StringValue('')});
  }
}

FileAssociationService getFileAssociationService() =>
    _FileAssociationNative();
