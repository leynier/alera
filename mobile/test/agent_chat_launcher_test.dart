import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_launcher.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_composer_draft.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_agent_chat_client.dart';

ProviderContainer _container(FakeAgentChatClient client) {
  final container = ProviderContainer(
    overrides: [
      mobileAgentChatClientProvider('host').overrideWith((ref) async => client),
    ],
  );
  addTearDown(container.dispose);
  // The workspace screen keeps these warm while chats are offered.
  container
    ..listen(agentChatProvidersProvider('host', 'workspace-1'), (_, _) {})
    ..listen(agentChatPreferencesProvider('host', null), (_, _) {});
  return container;
}

FakeAgentChatClient _client({
  Set<String>? capabilities,
  List<Map<String, Object?>>? providers,
  List<Map<String, Object?>> chats = const <Map<String, Object?>>[],
}) {
  final client = FakeAgentChatClient(capabilities: capabilities);
  client.handlers['agentChat.providers'] = (_) => <String, Object?>{
    'providers':
        providers ??
        <Object?>[
          agentChatProviderRow('cursor', available: false),
          agentChatProviderRow('codex', label: 'Codex'),
        ],
  };
  client.handlers['agentChat.list'] = (_) => <String, Object?>{'chats': chats};
  client.handlers['agentChat.create'] = (payload) => <String, Object?>{
    'chatId': 'chat-new',
    'tabId': 'tab-new',
    'snapshot': agentChatSnapshot(chatId: 'chat-new'),
  };
  return client;
}

Map<String, Object?> _summary(String chatId, {bool archived = false}) =>
    <String, Object?>{
      'chatId': chatId,
      'workspaceId': 'workspace-1',
      'title': 'Codex',
      'provider': 'codex',
      'providerInstanceId': 'codex',
      'status': 'stopped',
      'updatedAt': '2026-10-12T10:00:00Z',
      'tabId': 'tab-$chatId',
      'archived': archived,
    };

Future<AgentChatLaunchOutcome> _open(ProviderContainer container) async {
  final launcher = await agentChatLauncherFor(
    container.read,
    hostId: 'host',
    workspaceId: 'workspace-1',
  );
  return launcher.open(workspaceId: 'workspace-1', projectId: 'project');
}

void main() {
  test('New Chat creates at once with the first available agent', () async {
    final client = _client();
    final outcome = await _open(_container(client));

    expect(outcome, isA<AgentChatLaunchOpened>());
    expect((outcome as AgentChatLaunchOpened).tabId, 'tab-new');
    final payload = client.payloadsOf('agentChat.create').single;
    expect(payload['providerInstanceId'], 'codex');
    expect(payload.containsKey('model'), isFalse);
    expect(payload['workspaceId'], 'workspace-1');
  });

  test('an empty never-sent chat is focused instead of a second one', () async {
    final client = _client(chats: <Map<String, Object?>>[_summary('chat-1')])
      ..handlers['agentChat.snapshot'] = (_) => agentChatSnapshot();
    final outcome = await _open(_container(client));

    expect(outcome, isA<AgentChatLaunchOpened>());
    final opened = outcome as AgentChatLaunchOpened;
    expect(opened.reused, isTrue);
    expect(opened.chatId, 'chat-1');
    expect(client.payloadsOf('agentChat.create'), isEmpty);
  });

  test('a never-sent chat with text typed here is not reused', () async {
    final client = _client(chats: <Map<String, Object?>>[_summary('chat-1')])
      ..handlers['agentChat.snapshot'] = (_) => agentChatSnapshot();
    final container = _container(client);
    container
        .read(agentChatDraftStoreProvider)
        .write(
          'host',
          'chat-1',
          const AgentChatComposerDraft(
            value: TextEditingValue(text: 'half a thought'),
          ),
        );
    await _open(container);
    expect(client.payloadsOf('agentChat.create'), hasLength(1));
  });

  test('a retry after a lost connection reuses the request id', () async {
    final client = _client();
    var attempts = 0;
    client.handlers['agentChat.create'] = (_) {
      attempts += 1;
      if (attempts == 1) throw StateError('closed');
      return <String, Object?>{
        'chatId': 'chat-new',
        'tabId': 'tab-new',
        'snapshot': agentChatSnapshot(chatId: 'chat-new'),
      };
    };
    final container = _container(client);
    await expectLater(_open(container), throwsA(anything));
    await _open(container);
    final ids = <Object?>[
      for (final payload in client.payloadsOf('agentChat.create'))
        payload['requestId'],
    ];
    expect(ids, hasLength(2));
    expect(ids.first, ids.last);
  });

  test('no enabled agent creates nothing on an older runtime', () async {
    final client = _client(
      providers: <Map<String, Object?>>[
        agentChatProviderRow('codex', enabled: false),
      ],
    );
    final outcome = await _open(_container(client));
    expect(outcome, isA<AgentChatLaunchNoAgent>());
    expect(client.payloadsOf('agentChat.create'), isEmpty);
  });

  test('a runtime that keeps unselected drafts gets one', () async {
    final client = _client(
      capabilities: <String>{
        AgentChatWire.capability,
        AgentChatWire.unselectedDraftCapability,
      },
      providers: <Map<String, Object?>>[
        agentChatProviderRow('codex', enabled: false),
      ],
    );
    await _open(_container(client));
    final payload = client.payloadsOf('agentChat.create').single;
    expect(payload.containsKey('providerInstanceId'), isFalse);
    expect(payload.containsKey('provider'), isFalse);
  });

  group('agentChatLaunchSelection', () {
    const codex = AgentChatProviderInstance(
      id: 'codex',
      provider: 'codex',
      label: 'Codex',
    );
    const claude = AgentChatProviderInstance(
      id: 'claudeAgent',
      provider: 'claudeAgent',
      label: 'Claude',
    );
    const cursorOffline = AgentChatProviderInstance(
      id: 'cursor',
      provider: 'cursor',
      label: 'Cursor',
      available: false,
    );

    test('the project default wins over everything else', () {
      final selection = agentChatLaunchSelection(
        providers: const <AgentChatProviderInstance>[codex, claude],
        preferences: const AgentChatPreferences(
          projectDefaults: <String, AgentChatSelection>{
            'project': AgentChatSelection(providerInstanceId: 'claudeAgent'),
          },
          defaultSelection: AgentChatSelection(providerInstanceId: 'codex'),
        ),
        projectId: 'project',
      );
      expect(selection?.providerInstanceId, 'claudeAgent');
    });

    test('the launching chat counts only in the same workspace', () {
      const launching = AgentChatSelection(providerInstanceId: 'claudeAgent');
      final same = agentChatLaunchSelection(
        providers: const <AgentChatProviderInstance>[codex, claude],
        preferences: const AgentChatPreferences(),
        workspaceId: 'workspace-1',
        launchingSelection: launching,
        launchingWorkspaceId: 'workspace-1',
      );
      final other = agentChatLaunchSelection(
        providers: const <AgentChatProviderInstance>[codex, claude],
        preferences: const AgentChatPreferences(),
        workspaceId: 'workspace-1',
        launchingSelection: launching,
        launchingWorkspaceId: 'workspace-2',
      );
      expect(same?.providerInstanceId, 'claudeAgent');
      expect(other?.providerInstanceId, 'codex');
    });

    test('an enabled but unready default still names the agent', () {
      final selection = agentChatLaunchSelection(
        providers: const <AgentChatProviderInstance>[cursorOffline],
        preferences: const AgentChatPreferences(
          defaultSelection: AgentChatSelection(providerInstanceId: 'cursor'),
        ),
      );
      expect(selection?.providerInstanceId, 'cursor');
    });
  });
}
