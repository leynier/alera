import 'dart:async';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:alera/src/shared/infra/git/git_workspace_comparison.dart';
import 'package:alera/src/shared/infra/git/runtime_git_backend.dart';
import 'package:flutter_test/flutter_test.dart';

class _Client implements RuntimeHostClient, RuntimeHostCapabilityClient {
  bool supported = true;
  Object? error;
  final calls = <(String, Map<String, Object?>)>[];
  final snapshot = const GitWorkspaceComparison(
    baseRef: 'origin/main',
    baseOid: 'base',
    headOid: 'head',
    headRef: 'refs/heads/feature',
    treeOid: 'tree',
    indexOid: 'index',
    entries: [],
    added: 2,
    removed: 1,
  );
  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();
  @override
  Future<bool> supportsRuntimeCapability(String capability) async {
    expect(capability, 'workspaceDetailsV1');
    return supported;
  }

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const {},
    Duration? timeout,
  ]) async {
    calls.add((type, payload));
    if (error != null) throw error!;
    return switch (type) {
      'git.workspaceDefaultBranch' => 'main',
      'git.workspaceComparison' => snapshot.toJson(),
      'git.workspaceComparisonDiff' => {'files': [], 'truncated': false},
      _ => 'commit-oid',
    };
  }
}

void main() {
  test(
    'comparison, lazy diff and selective commit stay on the owning host',
    () async {
      final client = _Client();
      final git = RuntimeGitBackend(client, workspaceId: 'remote-workspace');
      expect(await git.workspaceDefaultBranch(r'C:\checkout'), 'main');
      final comparison = await git.workspaceComparison(
        r'C:\checkout',
        baseRef: 'origin/main',
      );
      expect(comparison.added, 2);
      expect(comparison.removed, 1);
      await git.workspaceComparisonDiff(r'C:\checkout', comparison, 'a.txt');
      expect(
        await git.commitSelected(r'C:\checkout', comparison, [
          'a.txt',
        ], 'reviewed'),
        'commit-oid',
      );
      for (final (_, payload) in client.calls) {
        expect(payload['workspaceId'], 'remote-workspace');
        expect(payload['path'], r'C:\checkout');
      }
      expect(client.calls.last.$2['snapshot'], comparison.toJson());
      expect(client.calls.last.$2['filePaths'], ['a.txt']);
    },
  );
  test('an old runtime does not receive unsupported operations', () async {
    final client = _Client()..supported = false;
    await expectLater(
      RuntimeGitBackend(
        client,
        workspaceId: 'w',
      ).workspaceComparison('/remote'),
      throwsA(isA<GitInternalException>()),
    );
    expect(client.calls, isEmpty);
  });
  test(
    'a disconnected host surfaces the failure without retrying the commit',
    () async {
      final client = _Client()..error = StateError('host disconnected');
      await expectLater(
        RuntimeGitBackend(
          client,
          workspaceId: 'remote-workspace',
        ).commitSelected('/remote', client.snapshot, [
          'selected.txt',
        ], 'reviewed'),
        throwsA(
          isA<GitInternalException>().having(
            (error) => error.context,
            'context',
            contains('disconnected'),
          ),
        ),
      );
      expect(client.calls.length, 1);
      expect(client.calls.single.$1, 'git.commitSelected');
      expect(client.calls.single.$2['workspaceId'], 'remote-workspace');
    },
  );
}
