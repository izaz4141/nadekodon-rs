import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nadekodon/utils/io_service.dart';

/// Exercises the real service through the same factory the app uses, so the
/// conditional import resolves the native implementation exactly as it does at
/// runtime.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late IOService io;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('nadekodon_io_service_test');
    io = IOServiceFactory.create();
  });

  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  String path(String name) => '${sandbox.path}/$name';

  group('files', () {
    test('writeFile then readFile round-trips', () async {
      await io.writeFile(path('a.txt'), 'hello');
      expect(await io.readFile(path('a.txt')), 'hello');
    });

    test('writeFile creates missing parent directories', () async {
      final nested = path('deep/er/still/a.txt');
      await io.writeFile(nested, 'nested');
      expect(await io.readFile(nested), 'nested');
    });

    // The single instance lock file is read by a second process, so the
    // flush has to survive the write and not just the close.
    test('writeFile with flush: true round-trips', () async {
      await io.writeFile(path('lock'), '36933', flush: true);
      expect(await io.readFile(path('lock')), '36933');
    });

    test('fileExists goes false, true, false across deleteFile', () async {
      final file = path('gone.txt');
      expect(await io.fileExists(file), isFalse);

      await io.writeFile(file, 'x');
      expect(await io.fileExists(file), isTrue);

      await io.deleteFile(file);
      expect(await io.fileExists(file), isFalse);
    });

    test('deleteFile throws when the file is absent', () {
      expect(
        () => io.deleteFile(path('never-existed')),
        throwsA(isA<FileSystemException>()),
      );
    });
  });

  group('local channel', () {
    test('a sent message reaches the bound server intact', () async {
      final server = await io.bindLocalChannel();
      addTearDown(server.close);

      final received = Completer<String>();
      server.onMessage(received.complete);

      final channel = await io.connectLocalChannel(server.port);
      await channel.send('open\n/some/target path');

      expect(await received.future, 'open\n/some/target path');
    });

    test('a multi-line message keeps its newlines', () async {
      final server = await io.bindLocalChannel();
      addTearDown(server.close);

      final received = Completer<String>();
      server.onMessage(received.complete);

      final channel = await io.connectLocalChannel(server.port);
      await channel.send('open\nline one\nline two');

      expect(await received.future, 'open\nline one\nline two');
    });
  });
}
