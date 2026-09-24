import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/process/host_routed_process_runner.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/infra/process/remote_process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoteProcessRunner', () {
    test(
      'run sends the workspace, command, cwd, environment and budget',
      () async {
        final client = _FakeRuntimeHostClient()
          ..response = <String, Object?>{
            'exitCode': 0,
            'stdout': '{"number":7}',
            'stderr': '',
          };
        var migrated = 0;
        final runner = RemoteProcessRunner(
          client,
          workspaceId: 'workspace-1',
          beforeAccess: () async => migrated++,
        );

        final result = await runner.run(
          'gh',
          <String>['pr', 'view', '7'],
          workingDirectory: '/srv/checkout',
          environment: <String, String>{'GH_HOST': 'github.example.com'},
        );

        expect(result.exitCode, 0);
        expect(result.stdout, '{"number":7}');
        expect(migrated, 1);
        expect(client.types.single, 'host.process.run');
        expect(client.payloads.single, <String, Object?>{
          'workspaceId': 'workspace-1',
          'executable': 'gh',
          'arguments': <String>['pr', 'view', '7'],
          'cwd': '/srv/checkout',
          'environment': <String, String>{'GH_HOST': 'github.example.com'},
          'timeoutMs': remoteProcessRunTimeout.inMilliseconds,
        });
        expect(
          client.timeouts.single,
          greaterThan(remoteProcessRunTimeout),
          reason: 'the request must outlive the tool so the host reports it',
        );
      },
    );

    test('run omits the cwd and an empty environment', () async {
      final client = _FakeRuntimeHostClient()
        ..response = <String, Object?>{
          'exitCode': 1,
          'stderr': 'not logged in',
        };
      final runner = RemoteProcessRunner(client, workspaceId: 'workspace-1');

      final result = await runner.run('gh', const <String>[
        'auth',
        'status',
      ], environment: const <String, String>{});

      expect(result.exitCode, 1);
      expect(result.stdout, isEmpty);
      expect(result.stderr, 'not logged in');
      expect(client.payloads.single.containsKey('cwd'), isFalse);
      expect(client.payloads.single.containsKey('environment'), isFalse);
    });

    test(
      'a host failure becomes the ProcessException callers expect',
      () async {
        final client = _FakeRuntimeHostClient()
          ..error = const TerminalHostConflictException(
            code: 'state',
            message: 'failed to run gh: No such file or directory',
          );
        final runner = RemoteProcessRunner(client, workspaceId: 'workspace-1');

        await expectLater(
          runner.run('gh', const <String>['--version']),
          throwsA(
            isA<ProcessException>()
                .having((error) => error.executable, 'executable', 'gh')
                .having(
                  (error) => error.message,
                  'message',
                  contains('No such file'),
                ),
          ),
        );
      },
    );

    test('a malformed answer is a failure, not a successful run', () async {
      final client = _FakeRuntimeHostClient()..response = 'ok';
      final runner = RemoteProcessRunner(client, workspaceId: 'workspace-1');

      await expectLater(
        runner.run('gh', const <String>[]),
        throwsA(isA<ProcessException>()),
      );
    });

    test('start is refused rather than run on the wrong machine', () async {
      final client = _FakeRuntimeHostClient();
      final runner = RemoteProcessRunner(client, workspaceId: 'workspace-1');

      await expectLater(
        runner.start('claude', const <String>['-p']),
        throwsA(isA<ProcessException>()),
      );
      expect(client.types, isEmpty);
    });
  });

  group('HostRoutedProcessRunner', () {
    test(
      'routes by working directory and keeps pathless calls local',
      () async {
        final local = _RecordingRunner('local');
        final remote = _RecordingRunner('remote');
        final runner = HostRoutedProcessRunner(
          local: local,
          remoteFor: (path) => path.startsWith('/srv/') ? remote : null,
        );

        await runner.run('gh', const <String>[], workingDirectory: '/srv/repo');
        await runner.run(
          'gh',
          const <String>[],
          workingDirectory: '/home/me/repo',
        );
        await runner.run('gh', const <String>[]);
        await runner.run('gh', const <String>[], workingDirectory: '  ');

        expect(remote.runs, <String?>['/srv/repo']);
        expect(local.runs, <String?>['/home/me/repo', null, '  ']);
      },
    );
  });
}

final class _RecordingRunner implements ProcessRunner {
  _RecordingRunner(this.name);

  final String name;
  final runs = <String?>[];

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    runs.add(workingDirectory);
    return ProcessRunOutput(exitCode: 0, stdout: name, stderr: '');
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
  }) => throw UnimplementedError();
}

final class _FakeRuntimeHostClient implements RuntimeHostClient {
  Object? response;
  Object? error;
  final types = <String>[];
  final payloads = <Map<String, Object?>>[];
  final timeouts = <Duration?>[];
  final _events = StreamController<RuntimeHostEvent>.broadcast();

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    types.add(type);
    payloads.add(payload);
    timeouts.add(timeout);
    if (error case final failure?) {
      throw failure;
    }
    return response;
  }
}
