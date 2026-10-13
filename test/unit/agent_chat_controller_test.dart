import 'dart:async';

import 'package:alera/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_view_state.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_agent_chat_repository.dart';

void main() {
  late FakeAgentChatRepository repository;
  late ProviderContainer container;
  late int nextId;

  setUp(() {
    repository = FakeAgentChatRepository();
    nextId = 0;
    container = ProviderContainer(
      overrides: [
        agentChatRepositoryProvider.overrideWithValue(repository),
        agentChatIdGeneratorProvider.overrideWithValue(() => 'id-${nextId++}'),
        agentChatClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 10, 12, 10),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  final provider = agentChatControllerProvider('chat-1', 'ws-1');

  Future<AgentChatViewState> open() async {
    container.listen(provider, (_, _) {});
    await pumpEventQueue();
    return container.read(provider);
  }

  Map<String, Object?> change(int cursor, Map<String, Object?> delta) =>
      <String, Object?>{
        'chatId': 'chat-1',
        'workspaceId': 'ws-1',
        'cursor': cursor,
        'delta': delta,
      };

  test('applies changes that arrive while the snapshot is read', () async {
    final snapshot = Completer<AgentChatSnapshot>();
    repository.snapshots.add(() => snapshot.future);
    container.listen(provider, (_, _) {});
    await pumpEventQueue();
    repository
      ..emitChange(change(4, <String, Object?>{'title': 'Stale'}))
      ..emitChange(change(5, <String, Object?>{'title': 'Renamed'}));
    await pumpEventQueue();
    snapshot.complete(agentChatSnapshotFixture(cursor: 4));
    await pumpEventQueue();
    final state = container.read(provider);
    expect(state.phase, AgentChatPhase.ready);
    expect(state.thread!.cursor, 5);
    expect(state.thread!.title, 'Renamed');
    expect(repository.snapshotReads, 1);
  });

  test('a skipped cursor reloads the snapshot', () async {
    repository.snapshots
      ..add(() => agentChatSnapshotFixture(cursor: 1))
      ..add(() => agentChatSnapshotFixture(cursor: 9));
    await open();
    repository.emitChange(change(3, <String, Object?>{'title': 'Gap'}));
    await pumpEventQueue();
    expect(repository.snapshotReads, 2);
    expect(container.read(provider).thread!.cursor, 9);
  });

  test('an older runtime reads as unsupported without a snapshot', () async {
    repository.isSupported = false;
    final state = await open();
    expect(state.phase, AgentChatPhase.unsupported);
    expect(repository.snapshotReads, 0);
  });

  test('a failed first read can be retried', () async {
    var fail = true;
    repository.snapshots.add(() {
      if (fail) {
        throw const AgentChatRequestException(
          message: 'Chat not found.',
          code: AgentChatErrorCodes.chatNotFound,
        );
      }
      return agentChatSnapshotFixture();
    });
    final failed = await open();
    expect(failed.phase, AgentChatPhase.failed);
    expect(failed.loadError, 'This chat no longer exists on the runtime.');
    fail = false;
    await container.read(provider.notifier).retry();
    expect(container.read(provider).phase, AgentChatPhase.ready);
  });

  test('a sent message shows until the runtime stamps it', () async {
    repository.snapshots.add(() => agentChatSnapshotFixture());
    await open();
    final controller = container.read(provider.notifier);
    expect(controller.send('  Run the tests  '), isTrue);
    expect(container.read(provider).outgoing.single.text, 'Run the tests');
    await pumpEventQueue();
    final sent = repository.calls.singleWhere((call) => call.$1 == 'send');
    final input = sent.$2! as AgentChatSendInput;
    expect(input.clientMessageId, 'id-0');
    expect(input.workspaceId, 'ws-1');
    expect(
      container.read(provider).outgoing.single.status,
      AgentChatOutgoingStatus.accepted,
    );
    repository.emitChange(
      change(2, <String, Object?>{
        'items': <Object?>[
          agentChatItemFixture(
            'u1',
            'user_message',
            text: 'Run the tests',
            clientMessageId: 'id-0',
          ),
        ],
      }),
    );
    await pumpEventQueue();
    final state = container.read(provider);
    expect(state.outgoing, isEmpty);
    expect(
      state.projection!.entries.whereType<AgentChatOutgoingEntry>(),
      isEmpty,
    );
  });

  test('a failed send keeps its id for the retry', () async {
    repository.snapshots.add(() => agentChatSnapshotFixture());
    repository.sendError = const AgentChatConnectionException('closed');
    await open();
    final controller = container.read(provider.notifier);
    controller.send('Hello');
    await pumpEventQueue();
    final failed = container.read(provider).outgoing.single;
    expect(failed.status, AgentChatOutgoingStatus.failed);
    expect(failed.error, contains('not reachable'));
    repository.sendError = null;
    await controller.retrySend(failed.clientMessageId);
    final sends = repository.calls.where((call) => call.$1 == 'send').toList();
    expect(sends, hasLength(2));
    expect(
      (sends.last.$2! as AgentChatSendInput).clientMessageId,
      failed.clientMessageId,
    );
  });

  test('a dropped connection keeps the copy and reloads on return', () async {
    repository.snapshots
      ..add(() => agentChatSnapshotFixture(cursor: 1))
      ..add(() => agentChatSnapshotFixture(cursor: 7));
    await open();
    repository.events.add(const AgentChatConnectionLost());
    await pumpEventQueue();
    expect(
      container.read(provider).connection,
      AgentChatConnection.reconnecting,
    );
    expect(container.read(provider).canSend, isFalse);
    repository.events.add(const AgentChatResyncRequired());
    await pumpEventQueue();
    final state = container.read(provider);
    expect(state.connection, AgentChatConnection.live);
    expect(state.thread!.cursor, 7);
  });

  test('a request stays answered until the runtime removes it', () async {
    final request = <String, Object?>{
      'requestId': 'r1',
      'kind': 'command_execution_approval',
      'createdAt': '2026-10-12T10:00:00Z',
      'decisions': <Object?>['accept', 'decline'],
    };
    repository.snapshots.add(
      () => agentChatSnapshotFixture(requests: <Map<String, Object?>>[request]),
    );
    final opened = await open();
    final controller = container.read(provider.notifier);
    await controller.respond(
      opened.thread!.pendingRequests.single,
      const AgentChatApprovalResponse(AgentChatApprovalDecision.accept),
    );
    expect(container.read(provider).respondingRequestIds, <String>{'r1'});
    repository.emitChange(
      change(2, <String, Object?>{'requests': <Object?>[]}),
    );
    await pumpEventQueue();
    expect(container.read(provider).respondingRequestIds, isEmpty);
  });

  test('an answer another client gave first is not an error', () async {
    repository.snapshots.add(
      () => agentChatSnapshotFixture(
        requests: <Map<String, Object?>>[
          <String, Object?>{
            'requestId': 'r1',
            'kind': 'tool_user_input',
            'createdAt': '2026-10-12T10:00:00Z',
            'questions': <Object?>[
              <String, Object?>{'id': 'q', 'question': 'Which?'},
            ],
          },
        ],
      ),
    );
    repository.respondError = const AgentChatRequestException(
      message: 'Already answered.',
      code: AgentChatErrorCodes.requestResolved,
    );
    final opened = await open();
    await container
        .read(provider.notifier)
        .respond(
          opened.thread!.pendingRequests.single,
          const AgentChatUserInputResponse(<String, List<String>>{}),
        );
    expect(container.read(provider).actionError, isNull);
  });

  test('interrupt names the running turn and settles with it', () async {
    repository.snapshots.add(
      () => agentChatSnapshotFixture(status: 'running', activeTurnId: 't1'),
    );
    await open();
    await container.read(provider.notifier).interrupt();
    expect(repository.calls.last, ('interrupt', 't1'));
    expect(container.read(provider).interrupting, isTrue);
    repository.emitChange(
      change(2, <String, Object?>{
        'session': <String, Object?>{'status': 'ready'},
      }),
    );
    await pumpEventQueue();
    expect(container.read(provider).interrupting, isFalse);
  });

  test('a refused provider switch surfaces the runtime reason', () async {
    repository.snapshots.add(() => agentChatSnapshotFixture());
    repository.configureError = const AgentChatRequestException(
      message: 'busy',
      code: AgentChatErrorCodes.turnActive,
    );
    await open();
    final accepted = await container
        .read(provider.notifier)
        .configure(const AgentChatConfiguration(provider: 'claudeAgent'));
    expect(accepted, isFalse);
    expect(container.read(provider).configuring, isFalse);
    expect(
      container.read(provider).actionError,
      contains('Wait for the current turn'),
    );
  });
}
