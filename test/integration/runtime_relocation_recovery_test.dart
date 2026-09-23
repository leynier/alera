import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/runtime_buffer_guard_handler.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/features/workbench/infra/workspace_relocation_recovery_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class _ExistingHostOnly implements TerminalHostProcessLauncher {
  @override
  Future<void> start({
    required String runtimeDir,
    required String controlFilePath,
    required String token,
    required TerminalHostConfig config,
  }) async {
    throw StateError(
      'This fixture must connect to its explicitly started host',
    );
  }
}

class _Buffers implements RuntimeBufferGuardHandler {
  bool blocked = false;
  int checks = 0;
  @override
  List<Map<String, Object?>> lock({
    required String guardId,
    required Set<String> tabIds,
    required Set<String> workspacePaths,
  }) {
    checks++;
    return blocked
        ? [
            {
              'tabId': 'fixture-editor',
              'path': workspacePaths.firstOrNull ?? '/fixture',
              'reason': 'Unsaved fixture buffer',
            },
          ]
        : [];
  }

  @override
  void release(String guardId, {bool retired = false}) {}
}

Future<String> _command(
  String executable,
  List<String> args,
  Map<String, String> environment,
) async {
  final child = await Process.start(
    executable,
    args,
    environment: environment,
    includeParentEnvironment: false,
  );
  final output = child.stdout.transform(utf8.decoder).join();
  final errors = child.stderr.transform(utf8.decoder).join();
  final code = await child.exitCode.timeout(
    const Duration(seconds: 45),
    onTimeout: () async {
      child.kill();
      await child.exitCode;
      throw StateError(
        'Fixture command timed out: $executable ${args.firstOrNull}',
      );
    },
  );
  final stdout = await output;
  final stderr = await errors;
  if (code != 0) {
    throw StateError('$executable ${args.firstOrNull} failed: $stderr');
  }
  return stdout;
}

void main() {
  final binary = Platform.environment['ALERA_RECOVERY_TEST_BINARY'];
  test(
    'desktop client resumes the saved operation after the real runtime restarts',
    () async {
      expect(File(binary!).existsSync(), isTrue);
      final root = await Directory.systemTemp.createTemp(
        'alera-recovery-client-',
      );
      final support = Directory(p.join(root.path, 'support'));
      final runtime = p.join(support.path, 'terminal_host');
      final repository = p.join(root.path, 'repository');
      final linked = p.join(root.path, 'linked');
      final config = File(p.join(root.path, 'git-config'));
      await config.writeAsString('');
      final environment = {...Platform.environment}
        ..removeWhere(
          (key, _) => key.startsWith('ALERA_') || key.startsWith('GIT_'),
        );
      environment['GIT_CONFIG_GLOBAL'] = config.path;
      environment['GIT_CONFIG_NOSYSTEM'] = '1';
      Future<Map<String, Object?>> cli(String group, List<String> args) async =>
          Map<String, Object?>.from(
            jsonDecode(
              await _command(binary, [
                group,
                '--runtime-dir',
                runtime,
                '--json',
                ...args,
              ], environment),
            ) as Map,
          );
      Future<void> git(List<String> args) async {
        await _command('git', args, environment);
      }

      SocketTerminalHostClient? connected;
      var started = false;
      try {
        await git(['init', '--initial-branch', 'main', repository]);
        final file = File(p.join(repository, 'retained.txt'));
        await file.writeAsString('committed\n');
        await git(['-C', repository, 'add', 'retained.txt']);
        await git([
          '-C',
          repository,
          '-c',
          'user.name=Fixture',
          '-c',
          'user.email=fixture@example.invalid',
          '-c',
          'commit.gpgsign=false',
          'commit',
          '-m',
          'fixture',
        ]);
        await cli('runtime', ['start']);
        started = true;
        final registration = await cli('project', [
          'add',
          '--name',
          'Fixture Project',
          '--repo-path',
          repository,
        ]);
        final source = Workspace.fromJson(
          Map<String, Object?>.from(registration['initialWorkspace'] as Map),
        );
        final sibling = await cli('workspace', [
          'add',
          '--project-id',
          source.projectId,
          '--name',
          'Neighbor',
        ]);
        final neighbor = Workspace.fromJson(
          Map<String, Object?>.from(sibling['workspace'] as Map),
        );
        final id = const Uuid().v4();
        await file.writeAsString('shared uncommitted changes\n');
        final prepared = await cli('project', [
          'relocate-owner-workspace',
          '--state-dir',
          runtime,
          '--prepare-only',
          '--request-base64',
          base64Encode(
            utf8.encode(
              jsonEncode({
                'workspace': source.toMap(),
                'relocationId': id,
                'intent': {
                  'workspaceId': source.id,
                  'toProjectCheckout': false,
                  'destinationPath': linked,
                  'branch': 'saved-topic',
                  'replacementBranch': null,
                  'moveChanges': false,
                  'sharedImpactConfirmed': true,
                },
              }),
            ),
          ),
        ]);
        expect(prepared['prepared'], isTrue);
        expect(await Directory(linked).exists(), isFalse);
        final buffers = _Buffers();
        SocketTerminalHostClient connect() => SocketTerminalHostClient(
          launcher: _ExistingHostOnly(),
          applicationSupportDirectory: () async => support,
          bufferGuardHandler: buffers,
        );
        connected = connect();
        final before = await WorkspaceRelocationRecoveryClient(connected)
            .inspect(source);
        expect(before.entries.single.id, id);
        expect(before.entries.single.completed, isFalse);
        connected.dispose();
        connected = null;
        await cli('runtime', ['stop', '--force']);
        started = false;
        await cli('runtime', ['start']);
        started = true;
        connected = connect();
        final recovery = WorkspaceRelocationRecoveryClient(connected);
        final after = await recovery.inspect(source);
        expect(after.entries.single.id, id);
        expect(after.entries.single.branch, 'saved-topic');
        buffers.blocked = true;
        await expectLater(
          recovery.resume(
            source,
            after.entries.single,
            sharedImpactConfirmed: true,
          ),
          throwsA(
            predicate(
              (error) => error.toString().contains('Unsaved fixture buffer'),
            ),
          ),
        );
        expect(await Directory(linked).exists(), isFalse);
        buffers.blocked = false;
        final result = await recovery.resume(
          source,
          after.entries.single,
          sharedImpactConfirmed: true,
        );
        expect(result.workspace.id, source.id);
        expect(result.workspace.instanceId, source.instanceId);
        expect(result.workspace.name, source.name);
        expect(result.workspace.path, linked);
        expect(await file.readAsString(), 'shared uncommitted changes\n');
        expect(
          await File(p.join(linked, 'retained.txt')).readAsString(),
          'committed\n',
        );
        expect(buffers.checks, greaterThanOrEqualTo(2));
        final persisted = await recovery.inspect(result.workspace);
        expect(persisted.entries.single.id, id);
        expect(persisted.entries.single.completed, isTrue);
        final listed = await connected.runtimeRequest('workspace.listAll');
        final unchanged = (listed as List).cast<Map>().singleWhere(
          (item) => item['id'] == neighbor.id,
        );
        expect(unchanged['path'], source.path);
        expect(unchanged['instanceId'], neighbor.instanceId);
        // A later edit must survive a completed-operation retry.
        await File(p.join(linked, 'later.txt'))
            .writeAsString('after completion\n');
        await recovery.resume(
          result.workspace,
          persisted.entries.single,
          sharedImpactConfirmed: true,
        );
        expect(
          await File(p.join(linked, 'later.txt')).readAsString(),
          'after completion\n',
        );
      } finally {
        connected?.dispose();
        if (started) await cli('runtime', ['stop', '--force']);
        expect(
          await File(p.join(runtime, 'runtime-host.json')).exists(),
          isFalse,
        );
        await root.delete(recursive: true);
      }
    },
    skip: binary == null
        ? 'Set ALERA_RECOVERY_TEST_BINARY to an isolated-test sidecar build'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
