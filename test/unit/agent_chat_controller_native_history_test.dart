import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_agent_chat_repository.dart';

const AgentChatNativeOperation _operation = AgentChatNativeOperation(
  operationId: 'op-1',
  state: 'uncertain',
  kind: 'rewind',
);

final class _NativeHistory extends AgentChatNativeHistoryRepository {
  final List<(String, AgentChatNativeHistoryAction, String)> reconciled =
      <(String, AgentChatNativeHistoryAction, String)>[];
  final List<bool> checkpoints = <bool>[];
  Object? nextError;

  @override
  Future<AgentChatNativeHistoryReconcileResult> reconcile(
    AgentChatRef chat, {
    required String requestId,
    required String operationId,
    required AgentChatNativeHistoryAction action,
    int? expectedRevision,
  }) async {
    reconciled.add((operationId, action, requestId));
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
    return AgentChatNativeHistoryReconcileResult(
      snapshot: agentChatSnapshotFixture(),
      operation: _operation,
    );
  }

  @override
  Future<AgentChatSnapshot> configureFileCheckpoints(
    AgentChatRef chat, {
    required String requestId,
    required bool enabled,
  }) async {
    checkpoints.add(enabled);
    return agentChatSnapshotFixture();
  }
}

final class _Lifecycle extends AgentChatLifecycleRepository
    implements AgentChatNativeHistoryAccess {
  @override
  final _NativeHistory nativeHistory = _NativeHistory();
}

void main() {
  late FakeAgentChatRepository repository;
  late _Lifecycle lifecycle;
  late ProviderContainer container;
  late int nextId;

  setUp(() {
    repository = FakeAgentChatRepository();
    lifecycle = _Lifecycle();
    nextId = 0;
    container = ProviderContainer(
      overrides: [
        agentChatComposerDraftsProvider.overrideWithValue(
          AgentChatComposerDrafts(),
        ),
        agentChatRepositoryProvider.overrideWithValue(repository),
        agentChatLifecycleRepositoryProvider.overrideWithValue(lifecycle),
        agentChatIdGeneratorProvider.overrideWithValue(() => 'id-${nextId++}'),
      ],
    );
  });

  tearDown(() => container.dispose());

  final provider = agentChatControllerProvider('chat-1', 'ws-1');

  Future<AgentChatController> open(AgentChatSnapshot snapshot) async {
    repository.snapshots.add(() => snapshot);
    container.listen(provider, (_, _) {});
    await pumpEventQueue();
    return container.read(provider.notifier);
  }

  final pending = agentChatSnapshotFixture(
    items: <Map<String, Object?>>[
      agentChatItemFixture('u1', 'user_message', text: 'Hello'),
    ],
  ).copyWith(pendingNativeOperation: _operation);

  test('a pending native operation blocks sending and reuse', () async {
    final controller = await open(pending);
    final state = container.read(provider);
    expect(state.nativeOperationPending, isTrue);
    expect(state.neverSent, isFalse);
    expect(controller.send('Not yet'), isFalse);
    expect(repository.calls.where((call) => call.$1 == 'send'), isEmpty);
  });

  test('a repeated choice for one operation reuses its request id', () async {
    final controller = await open(pending);
    lifecycle.nativeHistory.nextError = const AgentChatConnectionException(
      'Connection lost.',
    );
    await controller.reconcileNativeOperation(
      AgentChatNativeHistoryAction.restartFromTranscript,
    );
    expect(container.read(provider).actionError, isNotNull);
    expect(container.read(provider).reconcilingNativeOperation, isFalse);
    await controller.reconcileNativeOperation(
      AgentChatNativeHistoryAction.restartFromTranscript,
    );
    await controller.reconcileNativeOperation(
      AgentChatNativeHistoryAction.cancelUnstarted,
    );
    final calls = lifecycle.nativeHistory.reconciled;
    expect(calls, hasLength(3));
    expect(calls[0].$3, calls[1].$3);
    expect(calls[2].$3, isNot(calls[0].$3));
    expect(calls.every((call) => call.$1 == 'op-1'), isTrue);
  });

  test('file checkpointing changes only between turns', () async {
    final controller = await open(
      agentChatSnapshotFixture(status: 'running', activeTurnId: 'turn-1'),
    );
    expect(await controller.setFileCheckpointing(enabled: true), isFalse);
    expect(lifecycle.nativeHistory.checkpoints, isEmpty);
  });

  test('file checkpointing turns on from an idle chat', () async {
    final controller = await open(agentChatSnapshotFixture());
    expect(await controller.setFileCheckpointing(enabled: true), isTrue);
    expect(lifecycle.nativeHistory.checkpoints, <bool>[true]);
    // Already off: nothing to send.
    expect(await controller.setFileCheckpointing(enabled: false), isFalse);
  });
}
