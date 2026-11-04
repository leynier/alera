import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_view_state.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_agent_chat_repository.dart';

final class _Lifecycle extends AgentChatLifecycleRepository {
  final List<String?> forceStops = <String?>[];

  @override
  Future<bool> supports(String capability) async =>
      capability == AgentChatWire.forceStopCapability;

  @override
  Future<void> forceStop(
    AgentChatRef chat, {
    required String requestId,
    String? turnId,
  }) async => forceStops.add(turnId);
}

void main() {
  late FakeAgentChatRepository repository;
  late _Lifecycle lifecycle;
  late ProviderContainer container;

  setUp(() {
    repository = FakeAgentChatRepository();
    lifecycle = _Lifecycle();
    var nextId = 0;
    container = ProviderContainer(
      overrides: [
        agentChatComposerDraftsProvider.overrideWithValue(
          AgentChatComposerDrafts(),
        ),
        agentChatRepositoryProvider.overrideWithValue(repository),
        agentChatLifecycleRepositoryProvider.overrideWithValue(lifecycle),
        agentChatIdGeneratorProvider.overrideWithValue(() => 'id-${nextId++}'),
        agentChatClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 11, 2, 10),
        ),
      ],
    );
  });

  tearDown(() => container.dispose());

  final provider = agentChatControllerProvider('chat-1', 'ws-1');

  Map<String, Object?> change(int cursor, Map<String, Object?> delta) =>
      <String, Object?>{
        'chatId': 'chat-1',
        'workspaceId': 'ws-1',
        'cursor': cursor,
        'delta': delta,
      };

  Map<String, Object?> session(Map<String, Object?> stop) => <String, Object?>{
    'status': 'running',
    'activeTurnId': 't1',
    'runtimeMode': 'approval-required',
    'interactionMode': 'default',
    'capabilities': <String, Object?>{'interrupt': true},
    'stop': stop,
  };

  test('Stop reads Stopping until the runtime marks it unresponsive, '
      'then Force stop ends the turn', () async {
    repository.snapshots.add(
      () => agentChatSnapshotFixture(status: 'running', activeTurnId: 't1'),
    );
    container.listen(provider, (_, _) {});
    await pumpEventQueue();
    final controller = container.read(provider.notifier);
    await controller.interrupt();
    expect(container.read(provider).stopping, isTrue);
    expect(container.read(provider).canInterrupt, isFalse);

    repository.emitChange(
      change(2, <String, Object?>{
        'session': session(<String, Object?>{
          'turnId': 't1',
          'requestedAt': '2026-11-02T10:00:00Z',
        }),
      }),
    );
    await pumpEventQueue();
    expect(container.read(provider).stopping, isTrue);
    expect(container.read(provider).stopUnresponsive, isFalse);

    repository.emitChange(
      change(3, <String, Object?>{
        'session': session(<String, Object?>{
          'turnId': 't1',
          'requestedAt': '2026-11-02T10:00:00Z',
          'unresponsiveAt': '2026-11-02T10:00:15Z',
        }),
      }),
    );
    await pumpEventQueue();
    expect(container.read(provider).stopping, isFalse);
    expect(container.read(provider).stopUnresponsive, isTrue);

    await controller.forceStop();
    expect(lifecycle.forceStops, <String?>['t1']);
    expect(container.read(provider).forceStopping, isFalse);
  });

  test('a Stop left unanswered offers Force stop after the deadline', () {
    fakeAsync((async) {
      repository.snapshots.add(
        () => agentChatSnapshotFixture(status: 'running', activeTurnId: 't1'),
      );
      container.listen(provider, (_, _) {});
      async.flushMicrotasks();
      container.read(provider.notifier).interrupt();
      async.flushMicrotasks();
      expect(container.read(provider).stopUnresponsive, isFalse);
      async.elapse(agentChatForceStopAfter);
      expect(container.read(provider).stopUnresponsive, isTrue);
      expect(container.read(provider).stopping, isFalse);
    });
  });
}
