import 'package:alera_mobile/src/design_system/chips/alera_inline_chip.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_tab_view.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_agent_chat_client.dart';
import 'support/fake_ai_dictation_settings.dart';
import 'support/fake_terminal_client.dart';

const Key _suggestions = ValueKey<String>('agent-chat-composer-suggestions');

const List<Map<String, Object?>> _skills = <Map<String, Object?>>[
  <String, Object?>{
    'name': 'review',
    'path': '/s/review/SKILL.md',
    'enabled': true,
    'displayName': 'Code Review',
    'shortDescription': 'Review the diff',
  },
  <String, Object?>{
    'name': 'internal',
    'path': '/s/internal/SKILL.md',
    'enabled': true,
    'userInvocable': false,
  },
];

Future<FakeAgentChatClient> _pumpChat(
  WidgetTester tester, {
  bool skillsSupported = true,
  List<Map<String, Object?>> items = const <Map<String, Object?>>[],
}) async {
  final snapshot = agentChatSnapshot(
    items: items,
    turns: items.isEmpty
        ? const <Map<String, Object?>>[]
        : <Map<String, Object?>>[agentChatTurn('turn-1')],
  );
  final client = FakeAgentChatClient(
    capabilities: <String>{
      'agentChatV1',
      if (skillsSupported) 'agentChatSkillsV1',
    },
  );
  client.handlers['agentChat.snapshot'] = (_) => snapshot;
  client.handlers['agentChat.skills'] = (_) => <String, Object?>{
    'provider': 'codex',
    'providerInstanceId': 'codex',
    'status': 'ready',
    'source': 'session',
    'skills': _skills,
  };
  client.handlers['agentChat.providers'] = (_) => <String, Object?>{
    'providers': <Object?>[agentChatProviderRow('codex', label: 'Codex')],
  };
  final workspace = FakeTerminalClient();
  addTearDown(workspace.dispose);
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        agentChatDraftStoreProvider.overrideWithValue(AgentChatDraftStore()),
        mobileAgentChatClientProvider('host')
            .overrideWith((ref) async => client),
        workspaceClientProvider('host').overrideWith((ref) async => workspace),
        mobileAiDictationSettingsControllerProvider.overrideWith(
          FakeMobileAiDictationSettingsController.new,
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: AgentChatTabView(
            hostId: 'host',
            workspaceId: 'workspace-1',
            chatId: 'chat-1',
            provider: 'codex',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return client;
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.showKeyboard(find.byType(TextField));
  await tester.enterText(find.byType(TextField), text);
  await tester.pumpAndSettle();
}

String _composerText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  testWidgets(r'$ lists the skills a person can pick and a tap inserts one', (
    tester,
  ) async {
    final client = await _pumpChat(tester);
    await _type(tester, r'please $re');

    expect(find.byKey(_suggestions), findsOneWidget);
    expect(find.text('Skills'), findsOneWidget);
    expect(find.text('Code Review'), findsOneWidget);
    expect(find.text('Review the diff'), findsOneWidget);
    expect(find.text('Internal'), findsNothing);
    expect(client.payloadsOf('agentChat.skills'), isNotEmpty);

    await tester.tap(find.text('Code Review'));
    await tester.pumpAndSettle();
    expect(_composerText(tester), r'please $review ');
    expect(find.byKey(_suggestions), findsNothing);
  });

  testWidgets('/ lists skills as /skill:name', (tester) async {
    await _pumpChat(tester);
    await _type(tester, '/skill');

    expect(find.text('/skill:review'), findsOneWidget);
    await tester.tap(find.text('/skill:review'));
    await tester.pumpAndSettle();
    expect(_composerText(tester), r'$review ');
  });

  testWidgets(r'a host without skills leaves $ as plain text', (tester) async {
    final client = await _pumpChat(tester, skillsSupported: false);
    await _type(tester, r'say $re');

    expect(find.byKey(_suggestions), findsNothing);
    expect(client.payloadsOf('agentChat.skills'), isEmpty);
  });

  testWidgets('a sent message draws the skills it invoked as chips', (
    tester,
  ) async {
    await _pumpChat(
      tester,
      items: <Map<String, Object?>>[
        agentChatItem(
          'user-1',
          type: 'user_message',
          text: r'$review the diff, not $5',
        ),
      ],
    );

    final chip = find.byType(AleraInlineChip);
    expect(chip, findsOneWidget);
    expect(
      find.descendant(of: chip, matching: find.text('Code Review')),
      findsOneWidget,
    );
  });
}
