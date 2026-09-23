import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

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
    'mobile gateway resumes both directions with saved identities after runtime restart',
    () async {
      expect(File(binary!).existsSync(), isTrue);
      final created = await Directory.systemTemp.createTemp(
        'alera-mobile-recovery-',
      );
      final root = Directory(await created.resolveSymbolicLinks());
      final runtime = p.join(root.path, 'runtime');
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

      Future<String> prepare(
        Map<String, Object?> workspace, {
        required bool handOn,
      }) async {
        final id = const Uuid().v4();
        final prepared = await cli('project', [
          'relocate-owner-workspace',
          '--state-dir',
          runtime,
          '--prepare-only',
          '--request-base64',
          base64Encode(
            utf8.encode(
              jsonEncode({
                'workspace': workspace,
                'relocationId': id,
                'intent': {
                  'workspaceId': workspace['id'],
                  'toProjectCheckout': handOn,
                  'destinationPath': handOn ? null : linked,
                  'branch': handOn ? null : 'saved-topic',
                  'replacementBranch': null,
                  'moveChanges': handOn,
                  'sharedImpactConfirmed': true,
                },
              }),
            ),
          ),
        ]);
        expect(prepared['prepared'], isTrue);
        return id;
      }

      MobileRuntimeClient? connected;
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
        final rawSource = Map<String, Object?>.from(
          registration['initialWorkspace'] as Map,
        );
        final source = WorkspaceSummary.fromJson(rawSource);
        final sibling = await cli('workspace', [
          'add',
          '--project-id',
          source.projectId,
          '--name',
          'Neighbor',
        ]);
        final neighbor = WorkspaceSummary.fromJson(
          Map<String, Object?>.from(sibling['workspace'] as Map),
        );
        final reservation = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final port = reservation.port;
        await reservation.close();
        final settings = await cli('mobile', [
          'enable',
          '--bind-host',
          '127.0.0.1',
          '--port',
          '$port',
        ]);
        expect(settings['bindHost'], '127.0.0.1');
        final endpoint = 'ws://127.0.0.1:$port';
        final offer = await cli('mobile', [
          'pairing',
          'create',
          '--endpoint',
          endpoint,
          '--device-name',
          'Fixture Phone',
        ]);
        final device = await cli('mobile', [
          'pairing',
          'claim',
          '--pairing-id',
          offer['pairingId'] as String,
          '--pairing-secret',
          offer['pairingSecret'] as String,
          '--device-name',
          'Fixture Phone',
        ]);
        Future<MobileRuntimeClient> connect() async {
          final client = await MobileRuntimeClient.connect(endpoint);
          try {
            await client.authenticate(
              deviceId: device['deviceId'] as String,
              deviceToken: device['deviceToken'] as String,
            );
            expect(client.supportsWorkspaceRecovery, isTrue);
            return client;
          } catch (_) {
            await client.dispose();
            rethrow;
          }
        }

        await file.writeAsString('left in shared folder\n');
        final offId = await prepare(rawSource, handOn: false);
        connected = await connect();
        expect(
          (await connected.inspectWorkspaceRecovery(source)).entries.single.id,
          offId,
        );
        await connected.dispose();
        connected = null;
        await cli('runtime', ['stop', '--force']);
        started = false;
        await cli('runtime', ['start']);
        started = true;
        connected = await connect();
        final restored = await connected.inspectWorkspaceRecovery(source);
        expect(restored.entries.single.id, offId);
        final moved = await connected.resumeWorkspaceRecovery(
          source,
          restored.entries.single,
          sharedImpactConfirmed: true,
        );
        expect(moved.workspace.id, source.id);
        expect(moved.workspace.instanceId, source.instanceId);
        expect(moved.workspace.path, linked);
        expect(await file.readAsString(), 'left in shared folder\n');
        final records = await connected.request('workspace.listAll') as List;
        final rawMoved = Map<String, Object?>.from(
          records.cast<Map>().singleWhere((item) => item['id'] == source.id),
        );
        final unchanged = records.cast<Map>().singleWhere(
          (item) => item['id'] == neighbor.id,
        );
        expect(unchanged['path'], source.path);
        expect(unchanged['instanceId'], neighbor.instanceId);
        await file.writeAsString('committed\n');
        await File(p.join(linked, 'retained.txt'))
            .writeAsString('returned by mobile\n');
        final onId = await prepare(rawMoved, handOn: true);
        await connected.dispose();
        connected = null;
        await cli('runtime', ['stop', '--force']);
        started = false;
        await cli('runtime', ['start']);
        started = true;
        connected = await connect();
        final onHistory = await connected.inspectWorkspaceRecovery(
          moved.workspace,
        );
        expect(onHistory.entries.first.id, onId);
        expect(onHistory.entries.first.toProjectCheckout, isTrue);
        final returned = await connected.resumeWorkspaceRecovery(
          moved.workspace,
          onHistory.entries.first,
          sharedImpactConfirmed: true,
        );
        expect(returned.workspace.id, source.id);
        expect(returned.workspace.instanceId, source.instanceId);
        expect(returned.workspace.path, source.path);
        expect(await Directory(linked).exists(), isFalse);
        expect(await file.readAsString(), 'returned by mobile\n');
        final history = await connected.inspectWorkspaceRecovery(
          returned.workspace,
        );
        expect(history.entries.length, 2);
        expect(history.entries.every((entry) => entry.completed), isTrue);
        await file.writeAsString('after completed transfer\n');
        await connected.resumeWorkspaceRecovery(
          returned.workspace,
          history.entries.first,
          sharedImpactConfirmed: true,
        );
        expect(await file.readAsString(), 'after completed transfer\n');
      } finally {
        await connected?.dispose();
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
