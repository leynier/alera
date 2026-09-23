import 'dart:async';

import 'package:alera/src/features/linked_issues/infra/runtime_linked_issue_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

const _linked = <String, Object?>{
  'workspaceId': 'w1',
  'url': 'https://github.com/leynier/alera/issues/758',
  'provider': 'github',
  'number': 758,
  'title': 'Link an issue',
  'state': 'open',
  'linkedAt': '2026-09-12T21:18:27Z',
};

void main() {
  test('sends each verb with its payload and the fetch timeout', () async {
    final host = _FakeRuntimeHostClient(
      capabilities: <String>{aleraRuntimeHostLinkedIssuesCapability},
      respond: (type, _) {
        return switch (type) {
          'linkedIssue.list' => <String, Object?>{
            'items': <Object?>[_linked],
          },
          'linkedIssue.link' || 'linkedIssue.refresh' => <String, Object?>{
            'linkedIssue': _linked,
            'issue': null,
            'fetchError': <String, Object?>{
              'code': 'notAuthenticated',
              'message': 'Run gh auth login.',
            },
          },
          'issue.fetch' => <String, Object?>{
            'provider': 'github',
            'url': 'https://github.com/leynier/alera/issues/758',
            'number': 758,
            'title': 'Link an issue',
            'state': 'open',
          },
          _ => <String, Object?>{},
        };
      },
    );
    var migrated = 0;
    final repository = RuntimeLinkedIssueRepository(
      host,
      beforeAccess: () async => migrated++,
    );

    expect(await repository.isSupported(), isTrue);
    final all = await repository.listAll();
    expect(all.keys, <String>['w1']);
    final linked = await repository.link(
      'w1',
      'https://github.com/leynier/alera/issues/758',
    );
    expect(linked.fetchError!.code, 'notAuthenticated');
    await repository.refresh('w1');
    await repository.unlink('w1');
    final issue = await repository.fetch(
      'https://github.com/leynier/alera/issues/758',
    );
    expect(issue.title, 'Link an issue');

    expect(host.calls.map((call) => call.type), <String>[
      'linkedIssue.list',
      'linkedIssue.link',
      'linkedIssue.refresh',
      'linkedIssue.remove',
      'issue.fetch',
    ]);
    expect(host.calls[1].payload, <String, Object?>{
      'workspaceId': 'w1',
      'url': 'https://github.com/leynier/alera/issues/758',
    });
    expect(host.calls[1].timeout, linkedIssueFetchTimeout);
    expect(host.calls[3].timeout, isNull);
    expect(host.calls[4].payload, <String, Object?>{
      'url': 'https://github.com/leynier/alera/issues/758',
    });
    expect(migrated, 5);
  });

  test('an older host yields an unsupported empty snapshot', () async {
    final host = _FakeRuntimeHostClient(
      capabilities: const <String>{},
      respond: (_, _) => throw StateError('Unknown terminal host request'),
    );
    final repository = RuntimeLinkedIssueRepository(host);
    final snapshot = await repository.watchSnapshot().first;
    expect(snapshot.supported, isFalse);
    expect(snapshot.byWorkspace, isEmpty);
    expect(host.calls, isEmpty);
  });

  test('a supported host publishes links and refreshes on broadcast', () async {
    var title = 'First';
    final host = _FakeRuntimeHostClient(
      capabilities: const <String>{aleraRuntimeHostLinkedIssuesCapability},
      respond: (_, _) => <String, Object?>{
        'items': <Object?>[
          <String, Object?>{..._linked, 'title': title},
        ],
      },
    );
    final repository = RuntimeLinkedIssueRepository(host);
    final snapshots = repository.watchSnapshot();
    final received = <String?>[];
    final subscription = snapshots.listen(
      (snapshot) => received.add(snapshot.byWorkspace['w1']?.title),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    title = 'Second';
    host.emit(
      const RuntimeHostEvent('linkedIssuesChanged', <String, Object?>{
        'workspaceId': 'w1',
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await subscription.cancel();
    expect(received.first, 'First');
    expect(received.last, 'Second');
  });

  test('rejects malformed payloads', () async {
    final host = _FakeRuntimeHostClient(
      capabilities: const <String>{aleraRuntimeHostLinkedIssuesCapability},
      respond: (type, _) => type == 'issue.fetch'
          ? 'not an object'
          : <String, Object?>{'items': 'nope'},
    );
    final repository = RuntimeLinkedIssueRepository(host);
    await expectLater(repository.listAll(), throwsFormatException);
    await expectLater(repository.fetch('u'), throwsFormatException);
  });
}

class _Call {
  _Call(this.type, this.payload, this.timeout);
  final String type;
  final Map<String, Object?> payload;
  final Duration? timeout;
}

class _FakeRuntimeHostClient
    implements RuntimeHostClient, RuntimeHostCapabilityClient {
  _FakeRuntimeHostClient({required this.capabilities, required this.respond});

  final Set<String> capabilities;
  final Object? Function(String type, Map<String, Object?> payload) respond;
  final List<_Call> calls = <_Call>[];
  final StreamController<RuntimeHostEvent> _events =
      StreamController<RuntimeHostEvent>.broadcast();

  void emit(RuntimeHostEvent event) => _events.add(event);

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => _events.stream;

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    calls.add(_Call(type, payload, timeout));
    return respond(type, payload);
  }

  @override
  Future<bool> supportsRuntimeCapability(String capability) async =>
      capabilities.contains(capability);
}
