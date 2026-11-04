import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/shared/infra/files/posix_file_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../integration_test/agent_chat_benchmark_service.dart';

void main() {
  test(
    'omitted define does not inspect the service or write evidence',
    () async {
      await writeAgentChatBenchmarkServiceInfo(
        readServiceUri: () => throw StateError('Service must not be queried.'),
      );
    },
  );

  group('private benchmark service evidence', () {
    late Directory directory;
    late String outputPath;
    final validUri = Uri.parse('http://127.0.0.1:54321/test-auth=/');

    setUp(() async {
      final temporary = await Directory.systemTemp.createTemp('alera-bench-');
      directory = Directory(await temporary.resolveSymbolicLinks());
      expect(
        setPosixFileMode(directory.path, posixPrivateDirectoryMode),
        isTrue,
      );
      outputPath = p.join(directory.path, 'vm-service.json');
    });
    tearDown(() => directory.delete(recursive: true));

    Future<void> write({Uri? uri}) => writeAgentChatBenchmarkServiceInfo(
      outputPath: outputPath,
      readServiceUri: () async => uri ?? validUri,
    );

    test(
      'writes only current pid and authenticated URI with mode 0600',
      () async {
        await write();
        final file = File(outputPath);
        expect(jsonDecode(await file.readAsString()), <String, Object>{
          'pid': pid,
          'uri': validUri.toString(),
        });
        expect((await file.stat()).mode & 0xFFF, posixPrivateFileMode);
      },
    );

    test('accepts authenticated IPv6 loopback', () async {
      await write(uri: Uri.parse('http://[::1]:54321/test-auth=/'));
      expect(await File(outputPath).exists(), isTrue);
    });

    test('waits for service readiness before writing', () async {
      var reads = 0;
      await writeAgentChatBenchmarkServiceInfo(
        outputPath: outputPath,
        readServiceUri: () async => ++reads == 1 ? null : validUri,
      );
      expect(reads, 2);
      expect(await File(outputPath).exists(), isTrue);
    });

    for (final neverResponds in <bool>[false, true]) {
      test('bounds ${neverResponds ? 'pending' : 'absent'} service', () async {
        await expectLater(
          writeAgentChatBenchmarkServiceInfo(
            outputPath: outputPath,
            readinessTimeout: const Duration(milliseconds: 25),
            readServiceUri: neverResponds
                ? () => Completer<Uri?>().future
                : () async => null,
          ),
          throwsStateError,
        );
        expect(await File(outputPath).exists(), isFalse);
      });
    }

    test('rejects public parent without changing permissions', () async {
      expect(setPosixFileMode(directory.path, posixExecutableFileMode), isTrue);
      await expectLater(write(), throwsStateError);
      expect((await directory.stat()).mode & 0xFFF, posixExecutableFileMode);
      expect(await File(outputPath).exists(), isFalse);
    });

    test('rejects missing parent without creating it', () async {
      outputPath = p.join(directory.path, 'missing', 'vm-service.json');
      await expectLater(write(), throwsStateError);
      expect(await Directory(p.dirname(outputPath)).exists(), isFalse);
    });

    test('preserves existing evidence', () async {
      await File(outputPath).writeAsString('earlier evidence');
      await expectLater(write(), throwsStateError);
      expect(await File(outputPath).readAsString(), 'earlier evidence');
    });

    test(
      'rejects existing output symlink without changing its target',
      () async {
        final target = File(p.join(directory.path, 'target'));
        await target.writeAsString('untouched');
        await Link(outputPath).create(target.path);
        await expectLater(write(), throwsStateError);
        expect(await target.readAsString(), 'untouched');
      },
    );

    test('rejects a symlinked parent directory', () async {
      final alias = Link(p.join(directory.path, 'alias'));
      await alias.create(directory.path);
      outputPath = p.join(alias.path, 'vm-service.json');
      await expectLater(write(), throwsStateError);
      expect(
        await File(p.join(directory.path, 'vm-service.json')).exists(),
        isFalse,
      );
    });

    test('rejects malformed paths before service discovery', () async {
      for (final path in <String>[
        'vm-service.json',
        '$outputPath/',
        '$outputPath\u0000',
        '$outputPath\n',
        '${directory.path}/../vm-service.json',
        '${directory.path}//vm-service.json',
      ]) {
        await expectLater(
          writeAgentChatBenchmarkServiceInfo(
            outputPath: path,
            readServiceUri: () => throw StateError('Unexpected service query.'),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('clean absolute path'),
            ),
          ),
        );
      }
      expect(await File(outputPath).exists(), isFalse);
    });

    test('rejects unsafe service URIs without disclosing them', () async {
      for (final value in <String>[
        'http://0.0.0.0:54321/test-auth=/',
        'http://192.0.2.1:54321/test-auth=/',
        'http://localhost:54321/test-auth=/',
        'http://127.0.0.1:54321/',
        'http://127.0.0.1:54321/%20/',
        'http://127.0.0.1:54321/test-auth=/extra/',
        'http://127.0.0.1:54321/test-auth=/?query=1',
        'http://127.0.0.1:54321/test-auth=/#fragment',
        'http://user@127.0.0.1:54321/test-auth=/',
        'http://127.0.0.1/test-auth=/',
        'http://127.0.0.1:0/test-auth=/',
        'ws://127.0.0.1:54321/test-auth=/ws',
      ]) {
        await expectLater(
          write(uri: Uri.parse(value)),
          throwsA(
            isA<StateError>().having(
              (error) => error.toString(),
              'redacted message',
              isNot(contains('test-auth')),
            ),
          ),
        );
        expect(await File(outputPath).exists(), isFalse);
      }
    });
  }, skip: !Platform.isMacOS && !Platform.isLinux);
}
