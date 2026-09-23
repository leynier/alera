import 'dart:async';

import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/infra/runtime_workspace_search_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/rust/api/workspace_search.dart' as native;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('search sends the workspace id and parses the runtime result', () async {
    final client = _FakeRuntimeHostClient()
      ..responses['mobile.workspaceSearch.run'] = <String, Object?>{
        'files': <Object?>[
          <String, Object?>{
            'relativePath': 'lib/main.dart',
            'contentToken': 'token-1',
            'matches': <Object?>[
              <String, Object?>{
                'id': 'm1',
                'line': 3,
                'column': 7,
                'matchLength': 5,
                'lineContent': 'void hello() {}',
                'displayColumn': 8,
                'displayMatchLength': 5,
                'replacementPreview': null,
              },
            ],
          },
        ],
        'totalMatches': 1,
        'truncated': false,
      };
    final search = RuntimeWorkspaceSearchClient(
      client,
      workspaceId: 'workspace-1',
    );

    final result = await search.search(
      options: const native.WorkspaceSearchOptions(
        workspacePath: '/remote/checkout',
        query: 'hello',
        caseSensitive: false,
        wholeWord: true,
        useRegex: false,
        includePattern: ' lib/** ',
        excludePattern: '',
        includeIgnored: false,
      ),
      requestId: 'req-1',
    );

    final payload = client.payloads['mobile.workspaceSearch.run']!.single;
    expect(payload['workspaceId'], 'workspace-1');
    expect(payload['query'], 'hello');
    expect(payload['wholeWord'], isTrue);
    expect(payload['includePattern'], 'lib/**');
    expect(payload.containsKey('excludePattern'), isFalse);
    expect(payload.containsKey('workspacePath'), isFalse);
    expect(payload['requestId'], 'req-1');
    expect(result.totalMatches, 1);
    expect(result.truncated, isFalse);
    final file = result.files.single;
    expect(file.relativePath, 'lib/main.dart');
    expect(file.contentToken, 'token-1');
    final match = file.matches.single;
    expect(match.id, 'm1');
    expect(match.line, 3);
    expect(match.column, 7);
    expect(match.matchLength, 5);
    expect(match.displayColumn, 8);
    expect(match.replacementPreview, isNull);
  });

  test(
    'preview replace carries the replacement and wraps the result',
    () async {
      final client = _FakeRuntimeHostClient()
        ..responses['mobile.workspaceSearch.run'] = <String, Object?>{
          'files': <Object?>[],
          'totalMatches': 0,
          'truncated': true,
        };
      final search = RuntimeWorkspaceSearchClient(
        client,
        workspaceId: 'workspace-1',
      );

      final preview = await search.previewReplace(
        options: const native.WorkspaceReplaceOptions(
          search: native.WorkspaceSearchOptions(
            workspacePath: '/remote/checkout',
            query: 'a',
            caseSensitive: true,
            wholeWord: false,
            useRegex: true,
            includeIgnored: true,
          ),
          replacement: 'b',
          preserveCase: true,
        ),
        requestId: 'req-2',
      );

      final payload = client.payloads['mobile.workspaceSearch.run']!.single;
      expect(payload['replacement'], 'b');
      expect(payload['preserveCase'], isTrue);
      expect(payload['useRegex'], isTrue);
      expect(payload['includeIgnored'], isTrue);
      expect(preview.replacement, 'b');
      expect(preview.preserveCase, isTrue);
      expect(preview.result.truncated, isTrue);
    },
  );

  test(
    'replace forwards match ids and expectations and parses conflicts',
    () async {
      final client = _FakeRuntimeHostClient()
        ..responses['mobile.workspaceSearch.replace'] = <String, Object?>{
          'filesChanged': 1,
          'matchesReplaced': 2,
          'conflicts': <Object?>[
            <String, Object?>{'relativePath': 'b.txt', 'reason': 'changed'},
          ],
        };
      final search = RuntimeWorkspaceSearchClient(
        client,
        workspaceId: 'workspace-1',
      );

      final result = await search.replaceMatches(
        request: const native.WorkspaceReplaceRequest(
          options: native.WorkspaceReplaceOptions(
            search: native.WorkspaceSearchOptions(
              workspacePath: '/remote/checkout',
              query: 'a',
              caseSensitive: false,
              wholeWord: false,
              useRegex: false,
              includeIgnored: false,
            ),
            replacement: 'b',
            preserveCase: false,
          ),
          matchIds: <String>['m1', 'm2'],
          expectedFiles: <native.WorkspaceReplaceFileExpectation>[
            native.WorkspaceReplaceFileExpectation(
              relativePath: 'a.txt',
              contentToken: 'token-a',
            ),
          ],
        ),
      );

      final payload = client.payloads['mobile.workspaceSearch.replace']!.single;
      expect(payload['matchIds'], <String>['m1', 'm2']);
      expect(payload['expectedFiles'], <Object?>[
        <String, Object?>{'relativePath': 'a.txt', 'contentToken': 'token-a'},
      ]);
      expect(result.filesChanged, 1);
      expect(result.matchesReplaced, 2);
      expect(result.conflicts.single.relativePath, 'b.txt');
      expect(result.conflicts.single.reason, 'changed');
    },
  );

  test('runtime failures surface as workspace exceptions', () async {
    final client = _FakeRuntimeHostClient()
      ..onRequest = (type, payload) =>
          throw StateError('ssh target not found: mac-mini');
    final search = RuntimeWorkspaceSearchClient(
      client,
      workspaceId: 'workspace-1',
    );

    await expectLater(
      search.search(
        options: const native.WorkspaceSearchOptions(
          workspacePath: '/remote/checkout',
          query: 'a',
          caseSensitive: false,
          wholeWord: false,
          useRegex: false,
          includeIgnored: false,
        ),
        requestId: 'req-3',
      ),
      throwsA(isA<WorkspaceException>()),
    );
  });

  test('cancel swallows failures', () async {
    final client = _FakeRuntimeHostClient()
      ..onRequest = (type, payload) => throw StateError('offline');
    final search = RuntimeWorkspaceSearchClient(
      client,
      workspaceId: 'workspace-1',
    );

    await search.cancel(requestId: 'req-4');

    expect(
      client.payloads['mobile.workspaceSearch.cancel']!.single['requestId'],
      'req-4',
    );
  });
}

final class _FakeRuntimeHostClient implements RuntimeHostClient {
  final responses = <String, Object?>{};
  final payloads = <String, List<Map<String, Object?>>>{};
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
    return onRequest?.call(type, payload) ?? responses[type];
  }
}
