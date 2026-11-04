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

typedef _Chat = ({FakeAgentChatClient chat, FakeTerminalClient workspace});

Future<_Chat> _pumpChat(
  WidgetTester tester, {
  List<String> workspaceFiles = const <String>[],
  List<Map<String, Object?>> commands = const <Map<String, Object?>>[],
  double height = 900,
}) async {
  final snapshot = agentChatSnapshot(
    session: <String, Object?>{...agentChatSession(), 'commands': commands},
  );
  final client = FakeAgentChatClient();
  client.handlers['agentChat.snapshot'] = (_) => snapshot;
  client.handlers['agentChat.configure'] = (_) => <String, Object?>{
    'snapshot': <String, Object?>{...snapshot, 'cursor': 9},
  };
  client.handlers['agentChat.providers'] = (_) => <String, Object?>{
    'providers': <Object?>[
      <String, Object?>{
        ...agentChatProviderRow(
          'codex',
          label: 'Codex',
          models: <Map<String, Object?>>[
            <String, Object?>{'id': 'gpt-5', 'label': 'GPT-5'},
          ],
        ),
        'interactionModes': <String>['default', 'plan'],
      },
    ],
  };
  final workspace = FakeTerminalClient()..workspaceFiles = workspaceFiles;
  addTearDown(workspace.dispose);
  await tester.binding.setSurfaceSize(Size(420, height));
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
  return (chat: client, workspace: workspace);
}

/// Types [text] into the composer with the caret at its end and lets the
/// debounced file search answer.
Future<void> _type(WidgetTester tester, String text) async {
  await tester.showKeyboard(find.byType(TextField));
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pumpAndSettle();
}

String _composerText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  testWidgets('@ lists workspace files and a tap attaches one', (tester) async {
    final chat = await _pumpChat(
      tester,
      workspaceFiles: <String>['lib/main.dart', 'readme.md'],
    );

    await _type(tester, 'Read @mai');
    expect(find.byKey(_suggestions), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('main.dart'), findsOneWidget);
    expect(find.text('lib'), findsOneWidget);
    expect(find.text('readme.md'), findsNothing);
    expect(
      chat.workspace.calls,
      contains('startWorkspaceQuickOpen workspace-1'),
    );

    await tester.tap(find.text('main.dart'));
    await tester.pumpAndSettle();

    expect(find.byKey(_suggestions), findsNothing);
    expect(_composerText(tester), 'Read ');
    expect(find.widgetWithText(InputChip, 'main.dart'), findsOneWidget);
    // The field keeps the focus, so the keyboard stays up.
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
  });

  testWidgets('without Quick Open on the host an @ is plain text', (
    tester,
  ) async {
    await _pumpChat(tester);

    await _type(tester, 'mail @ma');

    expect(find.byKey(_suggestions), findsNothing);
    expect(_composerText(tester), 'mail @ma');
  });

  testWidgets('/ lists local commands, then the agent ones', (tester) async {
    await _pumpChat(
      tester,
      commands: <Map<String, Object?>>[
        <String, Object?>{
          'name': 'review',
          'description': 'Review a pull request',
        },
        <String, Object?>{
          'name': 'compact',
          'input': <String, Object?>{'hint': 'focus'},
        },
        <String, Object?>{'name': 'model', 'description': 'Clashes'},
      ],
    );

    await _type(tester, '/');
    expect(find.text('Commands'), findsOneWidget);
    expect(find.text('/model'), findsOneWidget);
    expect(find.text('Clashes'), findsNothing);
    expect(find.text('/plan'), findsOneWidget);
    expect(find.text('/review'), findsOneWidget);
    expect(find.text('Review a pull request'), findsOneWidget);
    expect(find.text('The agent has not reported usage yet.'), findsOneWidget);
    // Without a description the hint stands in.
    await _type(tester, '/comp');
    expect(find.text('/compact'), findsOneWidget);
    expect(find.text('focus'), findsOneWidget);

    await _type(tester, '/rev');
    await tester.tap(find.text('/review'));
    await tester.pumpAndSettle();

    expect(_composerText(tester), '/review ');
    expect(find.byKey(_suggestions), findsNothing);
  });

  testWidgets('/plan switches the mode and Close dismisses the list', (
    tester,
  ) async {
    final chat = await _pumpChat(tester);

    await _type(tester, '/pl');
    await tester.tap(find.text('/plan'));
    await tester.pumpAndSettle();

    expect(_composerText(tester), isEmpty);
    expect(
      chat.chat.payloadsOf('agentChat.configure').single['interactionMode'],
      'plan',
    );

    await _type(tester, '/mo');
    expect(find.byKey(_suggestions), findsOneWidget);
    await tester.tap(find.byTooltip('Close Suggestions'));
    await tester.pumpAndSettle();
    expect(find.byKey(_suggestions), findsNothing);
    expect(_composerText(tester), '/mo');
  });

  testWidgets('a short viewport squeezes the list, never the input', (
    tester,
  ) async {
    await _pumpChat(tester, height: 360);

    await _type(tester, '/');

    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
    final field = tester.getRect(find.byType(TextField));
    expect(field.bottom, lessThanOrEqualTo(360));
    final list = find.byKey(_suggestions);
    if (list.evaluate().isNotEmpty) {
      expect(tester.getRect(list).bottom, lessThanOrEqualTo(field.top));
    }
  });
}
