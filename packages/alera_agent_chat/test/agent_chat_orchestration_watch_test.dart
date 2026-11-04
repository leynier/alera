import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

typedef _Handler = FutureOr<Map<String, Object?>> Function(
  Map<String, Object?> payload,
);

final class _FakeTransport implements AgentChatTransport {
  _FakeTransport();

  bool capable = true;
  final List<(String, Map<String, Object?>, Duration?)> requests =
      <(String, Map<String, Object?>, Duration?)>[];
  final Map<String, _Handler> handlers = <String, _Handler>{};
  final StreamController<AgentChatTransportEvent> controller =
      StreamController<AgentChatTransportEvent>.broadcast(sync: true);

  @override
  Stream<AgentChatTransportEvent> get events => controller.stream;

  @override
  Future<bool> supportsCapability(String capability) async =>
      capable && capability == AgentChatOrchestrationWire.capability;

  @override
  Future<Map<String, Object?>> request(
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    requests.add((type, payload, timeout));
    final handler = handlers[type];
    return handler == null ? const <String, Object?>{} : await handler(payload);
  }

  void emit(String name, [Map<String, Object?> payload = const {}]) =>
      controller.add(AgentChatTransportEvent(name, payload));

  Iterable<String> get verbs => requests.map((request) => request.$1);
}

Map<String, Object?> _task(String id, {String status = 'running'}) =>
    <String, Object?>{
      'taskId': id,
      'status': status,
      'createdAt': '2026-10-12T10:00:00Z',
      'updatedAt': '2026-10-12T10:00:00Z',
    };

Map<String, Object?> _page(List<String> ids) => <String, Object?>{
  'tasks': <Object?>[for (final id in ids) _task(id)],
};

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('watchTasks', () {
    late _FakeTransport transport;
    late RuntimeAgentChatOrchestrationRepository repository;
    late List<Completer<Map<String, Object?>>> reads;

    setUp(() {
      transport = _FakeTransport();
      reads = <Completer<Map<String, Object?>>>[];
      transport.handlers[AgentChatOrchestrationWire.tasksList] = (_) {
        final read = Completer<Map<String, Object?>>();
        reads.add(read);
        return read.future;
      };
      repository = RuntimeAgentChatOrchestrationRepository(transport);
    });

    test('reads again only for changes that may touch the list', () async {
      final pages = <AgentChatTaskPage>[];
      final subscription = repository
          .watchTasks(const AgentChatTaskQuery(parentChatId: 'chat-1'))
          .listen(pages.add);
      await _settle();
      expect(reads, hasLength(1));
      reads.last.complete(_page(<String>['task-1']));
      await _settle();
      expect(pages.single.tasks.single.id, 'task-1');

      transport.emit(AgentChatOrchestrationWire.changedEvent, <String, Object?>{
        'taskId': 'task-9',
        'parentChatId': 'chat-other',
      });
      await _settle();
      expect(reads, hasLength(1), reason: 'another parent is ruled out');

      transport.emit(AgentChatOrchestrationWire.changedEvent, <String, Object?>{
        'taskId': 'task-2',
        'parentChatId': 'chat-1',
      });
      await _settle();
      expect(reads, hasLength(2));
      reads.last.complete(_page(<String>['task-2', 'task-1']));
      await _settle();

      transport.emit(AgentChatOrchestrationWire.changedEvent, <String, Object?>{
        'taskId': 'task-3',
      });
      await _settle();
      expect(reads, hasLength(3), reason: 'an absent field is a wildcard');
      reads.last.complete(_page(<String>['task-3']));
      await _settle();
      expect(pages.map((page) => page.tasks.length), <int>[1, 2, 1]);
      await subscription.cancel();
    });

    test('changes during a read fold into one more read', () async {
      final pages = <AgentChatTaskPage>[];
      final subscription = repository
          .watchTasks(const AgentChatTaskQuery())
          .listen(pages.add);
      await _settle();
      for (var index = 0; index < 5; index += 1) {
        transport.emit(AgentChatOrchestrationWire.changedEvent);
      }
      await _settle();
      expect(reads, hasLength(1));
      reads.last.complete(_page(<String>['task-1']));
      await _settle();
      expect(reads, hasLength(2));
      reads.last.complete(_page(<String>['task-1', 'task-2']));
      await _settle();
      expect(reads, hasLength(2));
      expect(pages.last.tasks, hasLength(2));
      await subscription.cancel();
    });

    test(
      'a disconnect drops the read in flight and a reconnect reads again',
      () async {
        final pages = <AgentChatTaskPage>[];
        final errors = <Object>[];
        final subscription = repository
            .watchTasks(const AgentChatTaskQuery())
            .listen(pages.add, onError: errors.add);
        await _settle();
        transport.emit(AgentChatTransportEvents.disconnected);
        reads.last.complete(_page(<String>['stale']));
        await _settle();
        expect(pages, isEmpty);
        expect(errors.single, isA<AgentChatConnectionException>());

        transport.emit(AgentChatTransportEvents.connected);
        await _settle();
        expect(reads, hasLength(2));
        reads.last.complete(_page(<String>['fresh']));
        await _settle();
        expect(pages.single.tasks.single.id, 'fresh');
        await subscription.cancel();
        transport.emit(AgentChatOrchestrationWire.changedEvent);
        await _settle();
        expect(reads, hasLength(2), reason: 'cancelled watches stop reading');
      },
    );

    test(
      'an older runtime surfaces Update Required without requests',
      () async {
        transport.capable = false;
        final errors = <Object>[];
        final subscription = repository
            .watchTasks(const AgentChatTaskQuery())
            .listen((_) {}, onError: errors.add);
        await _settle();
        expect(errors.single, isA<AgentChatOrchestrationUpdateRequired>());
        expect(transport.requests, isEmpty);
        await subscription.cancel();
      },
    );
  });

  test('watchTask follows only its own task and never acknowledges', () async {
    final transport = _FakeTransport()
      ..handlers[AgentChatOrchestrationWire.task] = (payload) =>
          <String, Object?>{'task': _task(payload['taskId']! as String)};
    final repository = RuntimeAgentChatOrchestrationRepository(transport);
    final tasks = <AgentChatTask>[];
    final subscription = repository.watchTask('task-1').listen(tasks.add);
    await _settle();
    transport
      ..emit(AgentChatOrchestrationWire.changedEvent, <String, Object?>{
        'taskId': 'task-2',
      })
      ..emit(AgentChatOrchestrationWire.changedEvent, <String, Object?>{
        'taskId': 'task-1',
      });
    await _settle();
    expect(tasks, hasLength(2));
    expect(
      transport.requests.every(
        (request) => !request.$2.containsKey('acknowledge'),
      ),
      isTrue,
    );
    await subscription.cancel();
  });

  test('changes map runtime events and reconnects', () async {
    final transport = _FakeTransport();
    final repository = RuntimeAgentChatOrchestrationRepository(transport);
    final changes = <AgentChatTaskChange>[];
    final subscription = repository.changes().listen(changes.add);
    transport
      ..emit(AgentChatOrchestrationWire.changedEvent, <String, Object?>{
        'taskId': 'task-1',
        'childChatId': 'chat-2',
      })
      ..emit('agentChatChanged', <String, Object?>{'chatId': 'chat-2'})
      ..emit(AgentChatTransportEvents.connected);
    await _settle();
    expect(changes, hasLength(2));
    expect(changes.first.taskId, 'task-1');
    expect(changes.first.childChatId, 'chat-2');
    expect(changes.last.taskId, isNull);
    await subscription.cancel();
  });
}
