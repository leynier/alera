import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_client_surfaces.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_tab_summary.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_agent_chat_client.dart';
import 'support/fake_ai_dictation_settings.dart';
import 'support/fake_terminal_client.dart';

/// The paired runtime with both the workspace surfaces and agent chats, as
/// the real client is.
class _ChatHost extends FakeTerminalClient implements MobileAgentChatClient {
  _ChatHost({Set<String>? capabilities})
    : chats = FakeAgentChatClient(capabilities: capabilities);

  final FakeAgentChatClient chats;

  @override
  Set<String> get runtimeCapabilities => chats.runtimeCapabilities;

  @override
  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) => chats.requestMap(type, payload, timeout);
}

const _chatTab = WorkspaceTabSummary(
  id: 'tab-chat',
  workspaceId: 'workspace-1',
  kind: 'agentChat',
  title: 'Fix the build',
  payload: <String, Object?>{
    'chatId': 'chat-1',
    'provider': 'codex',
    'providerInstanceId': 'codex',
  },
);

Future<_ChatHost> _pumpScreen(
  WidgetTester tester, {
  Set<String>? capabilities,
  String? initialTabId,
  void Function(_ChatHost host)? prepare,
}) async {
  final host = _ChatHost(capabilities: capabilities)
    ..tabs = <WorkspaceTabSummary>[
      fakeTab(id: 'tab-terminal', title: 'Shell'),
      _chatTab,
    ];
  host.chats.handlers['agentChat.snapshot'] = (_) => agentChatSnapshot();
  prepare?.call(host);
  addTearDown(host.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentChatDraftStoreProvider.overrideWithValue(AgentChatDraftStore()),
        terminalClientProvider('host').overrideWith((ref) async => host),
        workspaceClientProvider('host').overrideWith((ref) async => host),
        mobileAiDictationSettingsControllerProvider.overrideWith(
          FakeMobileAiDictationSettingsController.new,
        ),
      ],
      child: MaterialApp(
        home: WorkspaceTabsScreen(
          hostId: 'host',
          initialTabId: initialTabId,
          workspace: const WorkspaceSummary(
            id: 'workspace-1',
            projectId: 'project',
            name: 'Workspace',
            path: '/repo',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return host;
}

void main() {
  testWidgets('a chat tab opens its runtime chat next to the terminals', (
    tester,
  ) async {
    final host = await _pumpScreen(tester, initialTabId: 'tab-chat');
    expect(find.text('Fix the build'), findsOneWidget);
    expect(find.text('Shell'), findsOneWidget);
    // Nothing was sent yet, so the chat is ready rather than stopped.
    expect(find.text('Send a message to start.'), findsOneWidget);
    expect(
      host.chats.payloadsOf('agentChat.snapshot').single,
      <String, Object?>{'chatId': 'chat-1', 'workspaceId': 'workspace-1'},
    );
  });

  testWidgets('New Chat is offered only by runtimes that serve chats', (
    tester,
  ) async {
    await _pumpScreen(tester);
    await tester.tap(find.byTooltip('New Tab'));
    await tester.pumpAndSettle();
    expect(find.text('New Chat'), findsOneWidget);
    expect(find.text('Archived Chats'), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpScreen(tester, capabilities: <String>{});
    await tester.tap(find.byTooltip('New Tab'));
    await tester.pumpAndSettle();
    expect(find.text('New Chat'), findsNothing);
  });

  testWidgets('New Chat opens a chat at once, with no picker first', (
    tester,
  ) async {
    final host = await _pumpScreen(tester, prepare: _prepareCreate);
    expect(host.chats.payloadsOf('agentChat.create'), isEmpty);
    await tester.tap(find.byTooltip('New Tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Chat'));
    await tester.pumpAndSettle();

    expect(find.text('Start Chat'), findsNothing);
    final payload = host.chats.payloadsOf('agentChat.create').single;
    expect(payload['providerInstanceId'], 'codex');
    expect(payload['workspaceId'], 'workspace-1');
    expect(find.text('Send a message to start.'), findsOneWidget);
  });
}

void _prepareCreate(_ChatHost host) {
  host.chats.handlers['agentChat.providers'] = (_) => <String, Object?>{
    'providers': <Object?>[agentChatProviderRow('codex', label: 'Codex')],
  };
  host.chats.handlers['agentChat.list'] = (_) => <String, Object?>{
    'chats': <Object?>[],
  };
  host.chats.handlers['agentChat.create'] = (_) {
    host.tabs = <WorkspaceTabSummary>[
      ...host.tabs,
      const WorkspaceTabSummary(
        id: 'tab-new',
        workspaceId: 'workspace-1',
        kind: 'agentChat',
        title: 'Codex',
        payload: <String, Object?>{
          'chatId': 'chat-new',
          'provider': 'codex',
          'providerInstanceId': 'codex',
        },
      ),
    ];
    return <String, Object?>{
      'chatId': 'chat-new',
      'tabId': 'tab-new',
      'snapshot': agentChatSnapshot(chatId: 'chat-new'),
    };
  };
}
