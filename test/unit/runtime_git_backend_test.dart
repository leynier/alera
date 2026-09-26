import 'dart:async';
import 'dart:convert';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:alera/src/shared/infra/git/git_explorer_status.dart';
import 'package:alera/src/shared/infra/git/runtime_git_backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('status sends the workspace id and path and decodes entries', () async {
    final client = _FakeRuntimeHostClient()
      ..responses['git.status'] = <String, Object?>{
        'entries': <Object?>[
          <String, Object?>{
            'path': 'src/main.rs',
            'oldPath': null,
            'area': 'unstaged',
            'status': 'modified',
            'added': 2,
            'removed': 1,
            'isBinary': false,
            'isLarge': false,
            'submodule': null,
          },
          <String, Object?>{
            'path': 'notes.md',
            'area': 'untracked',
            'status': 'untracked',
          },
        ],
        'groups': <Object?>[
          <String, Object?>{
            'area': 'unstaged',
            'entries': <Object?>[],
            'treeRows': <Object?>[
              <String, Object?>{
                'kind': 'directory',
                'name': 'src',
                'path': 'src',
                'depth': 0,
                'fileCount': 1,
                'entry': null,
              },
            ],
          },
        ],
      };
    final backend = RuntimeGitBackend(client, workspaceId: 'workspace-1');

    final status = await backend.status('/remote/checkout');

    final payload = client.payloads['git.status']!.single;
    expect(payload['workspaceId'], 'workspace-1');
    expect(payload['path'], '/remote/checkout');
    expect(status.entries, hasLength(2));
    expect(status.entries.first.area, GitChangeArea.unstaged);
    expect(status.entries.first.status, GitChangeStatus.modified);
    expect(status.entries.first.added, 2);
    expect(status.entries.last.area, GitChangeArea.untracked);
    expect(
      status.groups.single.treeRows.single.kind,
      GitChangeTreeRowKind.directory,
    );
  });

  test('history decodes refs and epoch millisecond timestamps', () async {
    final client = _FakeRuntimeHostClient()
      ..responses['git.history'] = <String, Object?>{
        'items': <Object?>[
          <String, Object?>{
            'id': 'abc',
            'parentIds': <Object?>['def'],
            'subject': 'feat: one',
            'message': 'feat: one\n',
            'displayId': 'abc',
            'author': 'Alera',
            'authorEmail': 'alera@example.com',
            'timestamp': 1700000000000,
            'references': <Object?>[
              <String, Object?>{
                'id': 'refs/heads/main',
                'name': 'main',
                'revision': 'abc',
                'category': 'branches',
              },
            ],
          },
        ],
        'currentRef': <String, Object?>{
          'id': 'refs/heads/main',
          'name': 'main',
          'category': 'branches',
        },
        'hasIncomingChanges': false,
        'hasOutgoingChanges': true,
        'hasMore': false,
        'limit': 40,
      };
    final backend = RuntimeGitBackend(client, workspaceId: 'workspace-1');

    final history = await backend.history('/remote/checkout', limit: 40);

    expect(client.payloads['git.history']!.single['limit'], 40);
    expect(
      history.items.single.timestamp,
      DateTime.utc(2023, 11, 14, 22, 13, 20),
    );
    expect(
      history.items.single.references.single.category,
      GitHistoryRefCategory.branches,
    );
    expect(history.currentRef?.name, 'main');
    expect(history.hasOutgoingChanges, isTrue);
  });

  test(
    'mutations send their fields and network verbs use a longer timeout',
    () async {
      final client = _FakeRuntimeHostClient()
        ..responses['git.commit'] = <String, Object?>{'oid': 'deadbeef'};
      final backend = RuntimeGitBackend(client, workspaceId: 'workspace-1');

      await backend.stageArea(
        path: '/remote/checkout',
        area: GitChangeArea.untracked,
        filePath: 'notes.md',
      );
      final oid = await backend.commit(
        path: '/remote/checkout',
        message: 'feat: notes',
      );
      await backend.push('/remote/checkout');

      expect(client.payloads['git.stageArea']!.single['area'], 'untracked');
      expect(client.payloads['git.stageArea']!.single['filePath'], 'notes.md');
      expect(client.payloads['git.commit']!.single['message'], 'feat: notes');
      expect(oid, 'deadbeef');
      expect(
        client.timeouts['git.push']!.single,
        greaterThan(client.timeouts['git.commit']!.single!),
      );
    },
  );

  test('binary payloads are base64 decoded', () async {
    final client = _FakeRuntimeHostClient()
      ..responses['git.readingDiffPatch'] = <String, Object?>{
        'patchBase64': base64Encode(utf8.encode('diff --git a b\n')),
      }
      ..responses['git.diffBlobBytes'] = <String, Object?>{'bytesBase64': null};
    final backend = RuntimeGitBackend(client, workspaceId: 'workspace-1');

    final patch = await backend.readingDiffPatch(
      path: '/remote/checkout',
      area: GitChangeArea.staged,
    );
    final blob = await backend.diffBlobBytes(
      path: '/remote/checkout',
      filePath: 'logo.png',
      oldSide: true,
    );

    expect(utf8.decode(patch), 'diff --git a b\n');
    expect(client.payloads['git.readingDiffPatch']!.single['area'], 'staged');
    expect(client.payloads['git.diffBlobBytes']!.single['oldSide'], isTrue);
    expect(blob, isNull);
  });

  test('explorer status decodes into the snapshot map', () async {
    final client = _FakeRuntimeHostClient()
      ..responses['git.explorerStatus'] = <String, Object?>{
        'entries': <Object?>[
          <String, Object?>{'path': 'src', 'status': 'modified'},
          <String, Object?>{'path': 'src/main.rs', 'status': 'modified'},
          <String, Object?>{'path': 'notes.md', 'status': 'untracked'},
        ],
      };
    final backend = RuntimeGitBackend(client, workspaceId: 'workspace-1');

    final snapshot = await backend.explorerStatusSnapshot('/remote/checkout');

    expect(snapshot.statusFor('src'), GitExplorerStatus.modified);
    expect(snapshot.statusFor('notes.md'), GitExplorerStatus.untracked);
    expect(snapshot.statusFor('missing'), isNull);
  });

  test('a typed gitError conflict becomes the matching GitException', () async {
    final client = _FakeRuntimeHostClient()
      ..onRequest = (type, _) => throw const TerminalHostConflictException(
        code: runtimeGitErrorCode,
        message: 'nothing to commit',
        details: <String, Object?>{
          'kind': 'nothingToCommit',
          'context': 'nothing to commit',
        },
      );
    final backend = RuntimeGitBackend(client, workspaceId: 'workspace-1');

    await expectLater(
      backend.commit(path: '/remote/checkout', message: 'x'),
      throwsA(
        isA<NothingToCommitException>().having(
          (error) => error.context,
          'context',
          'nothing to commit',
        ),
      ),
    );
  });

  test('other runtime failures surface as GitInternalException', () async {
    final client = _FakeRuntimeHostClient()
      ..onRequest = (type, _) => throw StateError('link is down');
    final backend = RuntimeGitBackend(client, workspaceId: 'workspace-1');

    await expectLater(
      backend.repositoryState('/remote/checkout'),
      throwsA(isA<GitInternalException>()),
    );
  });

  test('worktree lifecycle is refused on a remote checkout', () async {
    final client = _FakeRuntimeHostClient();
    final backend = RuntimeGitBackend(client, workspaceId: 'workspace-1');

    await expectLater(
      backend.removeWorktree(repoPath: '/remote/repo', path: '/remote/wt'),
      throwsA(isA<GitInternalException>()),
    );
    expect(client.payloads, isEmpty);
  });
}

final class _FakeRuntimeHostClient implements RuntimeHostClient {
  final responses = <String, Object?>{};
  final payloads = <String, List<Map<String, Object?>>>{};
  final timeouts = <String, List<Duration?>>{};
  Object? Function(String type, Map<String, Object?> payload)? onRequest;
  final _events = StreamController<RuntimeHostEvent>.broadcast();

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    payloads.putIfAbsent(type, () => <Map<String, Object?>>[]).add(payload);
    timeouts.putIfAbsent(type, () => <Duration?>[]).add(timeout);
    return onRequest?.call(type, payload) ?? responses[type];
  }
}
