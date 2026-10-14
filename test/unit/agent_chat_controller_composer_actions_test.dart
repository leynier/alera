import 'package:alera/src/features/agent_chat/application/agent_chat_composer_drafts.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_agent_chat_repository.dart';

const Map<String, Object?> _steerCapabilities = <String, Object?>{
  'interrupt': true,
  'steer': true,
};

void main() {
  late FakeAgentChatRepository repository;
  late ProviderContainer container;
  late int nextId;

  setUp(() {
    repository = FakeAgentChatRepository();
    nextId = 0;
    container = ProviderContainer(
      overrides: [
        agentChatComposerDraftsProvider.overrideWithValue(
          AgentChatComposerDrafts(),
        ),
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

  Future<AgentChatController> open(AgentChatSnapshot snapshot) async {
    repository.snapshots.add(() => snapshot);
    container.listen(provider, (_, _) {});
    await pumpEventQueue();
    return container.read(provider.notifier);
  }

  List<AgentChatConfiguration> configurations() => <AgentChatConfiguration>[
    for (final call in repository.calls)
      if (call.$1 == 'configure') call.$2! as AgentChatConfiguration,
  ];

  List<AgentChatSendInput> sends() => <AgentChatSendInput>[
    for (final call in repository.calls)
      if (call.$1 == 'send') call.$2! as AgentChatSendInput,
  ];

  final userItem = <Map<String, Object?>>[
    agentChatItemFixture('u1', 'user_message', text: 'Hello'),
  ];

  test('a never-sent chat is reusable until a message leaves', () async {
    final controller = await open(agentChatSnapshotFixture());
    expect(container.read(provider).neverSent, isTrue);
    controller.send('First message');
    expect(container.read(provider).neverSent, isFalse);
  });

  test(
    'picking another agent sends one configure with an explicit reset',
    () async {
      final controller = await open(agentChatSnapshotFixture());
      await controller.choose(
        const AgentChatSelection(providerInstanceId: 'claudeAgent'),
        label: 'Claude',
      );
      final configuration = configurations().single;
      expect(configuration.providerInstanceId, 'claudeAgent');
      expect(configuration.toJson(), containsPair('model', null));
    },
  );

  test('a model the running turn cannot take waits for idle', () async {
    final controller = await open(
      agentChatSnapshotFixture(
        status: 'running',
        activeTurnId: 'turn-1',
        items: userItem,
      ),
    );
    await controller.choose(
      const AgentChatSelection(providerInstanceId: 'codex', model: 'gpt-6'),
      label: 'GPT 6',
    );
    expect(configurations(), isEmpty);
    expect(container.read(provider).pendingModel?.label, 'GPT 6');

    controller.send('Queue this');
    await pumpEventQueue();
    expect(sends().single.model, 'gpt-6');
    expect(container.read(provider).pendingModel, isNull);
  });

  test('a held provider default goes out as a reset once idle', () async {
    final controller = await open(
      agentChatSnapshotFixture(
        status: 'running',
        activeTurnId: 'turn-1',
        items: userItem,
      ),
    );
    await controller.choose(
      const AgentChatSelection(providerInstanceId: 'codex'),
      label: 'Codex',
    );
    repository.emitChange(<String, Object?>{
      'chatId': 'chat-1',
      'workspaceId': 'ws-1',
      'cursor': 2,
      'delta': <String, Object?>{
        'session': <String, Object?>{
          'status': 'ready',
          'model': 'gpt-5',
          'runtimeMode': 'approval-required',
          'interactionMode': 'default',
        },
      },
    });
    await pumpEventQueue();
    final configuration = configurations().single;
    expect(configuration.resetModel, isTrue);
    expect(configuration.toJson(), containsPair('model', null));
    expect(container.read(provider).pendingModel, isNull);
  });

  test('Mod+Enter steers only while the agent accepts it', () async {
    final controller = await open(
      agentChatSnapshotFixture(
        status: 'running',
        activeTurnId: 'turn-1',
        items: userItem,
        capabilities: _steerCapabilities,
      ),
    );
    expect(container.read(provider).canSteer, isTrue);
    controller.send('Also check the docs', delivery: AgentChatDelivery.steer);
    await pumpEventQueue();
    expect(sends().single.delivery, AgentChatDelivery.steer);
  });

  test('a steer without agent support falls back to auto delivery', () async {
    final controller = await open(
      agentChatSnapshotFixture(
        status: 'running',
        activeTurnId: 'turn-1',
        items: userItem,
      ),
    );
    expect(container.read(provider).canSteer, isFalse);
    controller.send('Later', delivery: AgentChatDelivery.steer);
    await pumpEventQueue();
    expect(sends().single.delivery, AgentChatDelivery.auto);
  });

  test('the first send remembers the selection for this session', () async {
    final controller = await open(agentChatSnapshotFixture());
    controller.send('Start');
    await pumpEventQueue();
    expect(
      container.read(agentChatLaunchPreferenceProvider),
      const AgentChatSelection(
        providerInstanceId: 'codex',
        model: 'gpt-5',
        runtimeMode: AgentChatRuntimeMode.approvalRequired,
        interactionMode: AgentChatInteractionMode.standard,
      ),
    );
  });

  test('taking a queued message back reports whether it was queued', () async {
    final controller = await open(
      agentChatSnapshotFixture(
        status: 'running',
        activeTurnId: 'turn-1',
        items: userItem,
      ),
    );
    expect(await controller.cancelQueued('q1'), isTrue);
    expect(repository.calls.last, ('cancelQueued', 'q1'));
  });

  test('queue edits report the reason on runtimes without the verb', () async {
    final controller = await open(agentChatSnapshotFixture(items: userItem));
    expect(await controller.editQueued('q1', 'New text'), isNotNull);
  });

  test('a chat removed elsewhere stays readable and stops sending', () async {
    final controller = await open(agentChatSnapshotFixture(items: userItem));
    repository.events.add(const AgentChatRemoved(discarded: true));
    await pumpEventQueue();
    final state = container.read(provider);
    expect(state.removed, isTrue);
    expect(state.thread, isNotNull);
    expect(state.canSend, isFalse);
    expect(controller.send('Too late'), isFalse);
  });
}
