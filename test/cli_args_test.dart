import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nadekodon/utils/cli_args.dart';
import 'package:nadekodon/utils/io_service.dart';

/// [ShowVersion] reads the version over a method channel, so the binding has to
/// exist and the plugin has to be answered by hand.
const _packageInfoChannel = MethodChannel(
  'dev.fluttercommunity.plus/package_info',
);

/// Stands in for the real filesystem and stdout. Only the three members
/// [parseCliArgs] can reach are implemented; anything else is a bug in the test.
class FakeIOService implements IOService {
  FakeIOService({this.existingFiles = const <String>{}});

  final Set<String> existingFiles;
  final List<String> output = <String>[];
  int? exitCode;

  @override
  Future<bool> fileExists(String path) async => existingFiles.contains(path);

  @override
  void writeLine(String line) => output.add(line);

  @override
  Never exit(int code) {
    exitCode = code;
    throw _Exited(code);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Exited implements Exception {
  const _Exited(this.code);
  final int code;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_packageInfoChannel, (call) async {
        if (call.method != 'getAll') return null;
        return <String, Object?>{
          'appName': 'Nadeko~don',
          'packageName': 'id.glicole.nadekodon',
          'version': '1.0.0',
          'buildNumber': '1',
          'buildSignature': '',
          'installerStore': null,
          'installTime': null,
          'updateTime': null,
        };
      });

  group('parseCliArgs', () {
    test('reports the version for -v and --version', () async {
      for (final flag in ['-v', '--version']) {
        final io = FakeIOService();
        final action = await parseCliArgs([flag], io);
        expect(action, isA<ShowVersion>());
      }
    });

    test('shows help for -h and --help', () async {
      for (final flag in ['-h', '--help']) {
        final action = await parseCliArgs([flag], FakeIOService());
        expect(action, isA<ShowHelp>());
      }
    });

    test('runs normally without arguments', () async {
      final action = await parseCliArgs([], FakeIOService());
      expect(action, isA<RunNormally>());
    });

    test('runs normally for an unrelated argument', () async {
      final action = await parseCliArgs(['--not-a-real-flag'], FakeIOService());
      expect(action, isA<RunNormally>());
    });

    test('a flag wins over a target', () async {
      final io = FakeIOService(existingFiles: {'/tmp/a.torrent'});
      final action = await parseCliArgs(['/tmp/a.torrent', '--version'], io);
      expect(action, isA<ShowVersion>());
    });

    test('accepts an existing local torrent path', () async {
      final io = FakeIOService(existingFiles: {'/tmp/a.torrent'});
      final action = await parseCliArgs(['/tmp/a.torrent'], io);
      expect((action as OpenTarget).target, '/tmp/a.torrent');
    });

    test('skips a local torrent path that is not there', () async {
      final io = FakeIOService();
      final action = await parseCliArgs(['/tmp/gone.torrent'], io);
      expect(action, isA<RunNormally>());
    });

    test('turns a file:// URI into a path', () async {
      final io = FakeIOService(existingFiles: {'/tmp/my torrent.torrent'});
      final action = await parseCliArgs([
        'file:///tmp/my%20torrent.torrent',
      ], io);
      expect((action as OpenTarget).target, '/tmp/my torrent.torrent');
    });

    test('accepts a magnet link without touching the filesystem', () async {
      const magnet = 'magnet:?xt=urn:btih:abc123&dn=example';
      final io = FakeIOService();
      final action = await parseCliArgs([magnet], io);
      expect((action as OpenTarget).target, magnet);
    });

    test('accepts an http url', () async {
      const url = 'https://example.com/file.iso';
      final action = await parseCliArgs([url], FakeIOService());
      expect((action as OpenTarget).target, url);
    });

    test('takes the first valid target when several are given', () async {
      final io = FakeIOService(existingFiles: {'/tmp/b.torrent'});
      final action = await parseCliArgs([
        '/tmp/gone.torrent',
        '/tmp/b.torrent',
        'magnet:?xt=urn:btih:z',
      ], io);
      expect((action as OpenTarget).target, '/tmp/b.torrent');
    });
  });

  group('CliAction.run', () {
    test('ShowVersion prints the version and exits cleanly', () async {
      final io = FakeIOService();
      final action = ShowVersion(io);

      await expectLater(action.run(), throwsA(isA<_Exited>()));

      expect(io.output.single, 'Nadeko~don 1.0.0+1');
      expect(io.exitCode, 0);
    });

    test('ShowHelp prints the usage and exits cleanly', () async {
      final io = FakeIOService();
      final action = ShowHelp(io);

      await expectLater(action.run(), throwsA(isA<_Exited>()));

      expect(io.output.single, contains('Usage:'));
      expect(io.exitCode, 0);
    });

    test('OpenTarget and RunNormally return without exiting', () async {
      final io = FakeIOService();

      await OpenTarget(io, '/tmp/a.torrent').run();
      await RunNormally(io).run();

      expect(io.output, isEmpty);
      expect(io.exitCode, isNull);
    });
  });
}
