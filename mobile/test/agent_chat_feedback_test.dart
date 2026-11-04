import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_draft_store.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_tab_view.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/runtime_request_error.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_agent_chat_client.dart';
import 'support/fake_ai_dictation_settings.dart';
import 'support/fake_terminal_client.dart';

Map<String, Object?> _codexSession() => <String, Object?>{
  ...agentChatSession(),
  'commands': <Map<String, Object?>>[
    <String, Object?>{'name': 'compact'},
    <String, Object?>{
      'name': 'feedback',
      'description': 'Send this thread and Codex logs to OpenAI',
    },
  ],
};

Future<FakeAgentChatClient> _pump(
  WidgetTester tester, {
  bool supported = true,
  bool sent = true,
}) async {
  final client = FakeAgentChatClient(
    capabilities: <String>{
      'agentChatV1',
      if (supported) AgentChatWire.feedbackCapability,
    },
  );
  client.handlers['agentChat.snapshot'] = (_) => agentChatSnapshot(
    session: _codexSession(),
    items: sent
        ? <Map<String, Object?>>[
            agentChatItem('u1', type: 'user_message', text: 'Fix it'),
          ]
        : const <Map<String, Object?>>[],
    turns: sent
        ? <Map<String, Object?>>[agentChatTurn('turn-1')]
        : const <Map<String, Object?>>[],
  );
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

String _composerText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byTooltip('Send'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('confirming /feedback uploads it and shows the thread id', (
    tester,
  ) async {
    final client = await _pump(tester);
    final answer = Completer<Map<String, Object?>>();
    client.handlers['agentChat.feedback'] = (_) => answer.future;

    await _send(tester, '/feedback The diff was empty');
    expect(find.text(agentChatFeedbackConsentTitle), findsOneWidget);
    expect(find.textContaining('Codex logs to OpenAI'), findsOneWidget);
    expect(client.payloadsOf('agentChat.feedback'), isEmpty);

    await tester.tap(find.text(agentChatFeedbackConsentConfirmLabel));
    await tester.pump();
    final payload = client.payloadsOf('agentChat.feedback').single;
    expect(payload['chatId'], 'chat-1');
    expect(payload['reason'], 'The diff was empty');
    expect(payload['requestId'], isA<String>());
    expect(_composerText(tester), isEmpty);
    expect(find.text('Sending feedback to OpenAI...'), findsOneWidget);
    expect(client.payloadsOf('agentChat.send'), isEmpty);

    // A second /feedback waits for the one in flight.
    await _send(tester, '/feedback ');
    expect(find.text(agentChatFeedbackConsentTitle), findsNothing);

    answer.complete(<String, Object?>{'feedbackId': 'thread-9'});
    await tester.pumpAndSettle();
    expect(
      find.text('Feedback sent to OpenAI\nThread ID: thread-9'),
      findsOneWidget,
    );
    expect(find.text('Copy ID'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Feedback sent to OpenAI'), findsNothing);
  });

  testWidgets('cancel keeps the draft and a failure says why', (tester) async {
    final client = await _pump(tester);
    client.handlers['agentChat.feedback'] = (_) => throw RuntimeRequestError(
      'Upload refused.',
      code: AgentChatErrorCodes.feedbackFailed,
    );

    await _send(tester, '/feedback ');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(_composerText(tester), '/feedback ');
    expect(client.payloadsOf('agentChat.feedback'), isEmpty);

    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(agentChatFeedbackConsentConfirmLabel));
    await tester.pumpAndSettle();
    expect(client.payloadsOf('agentChat.feedback').single['reason'], isNull);
    expect(
      find.text('Could not send feedback to OpenAI\nUpload refused.'),
      findsOneWidget,
    );
  });

  testWidgets('a chat with no message refuses /feedback as T3 Code does', (
    tester,
  ) async {
    final client = await _pump(tester, sent: false);
    await _send(tester, '/feedback');
    expect(find.text(agentChatFeedbackConsentTitle), findsNothing);
    expect(
      find.text(agentChatFeedbackNeedsConversationMessage),
      findsOneWidget,
    );
    expect(_composerText(tester), '/feedback');
    expect(client.payloadsOf('agentChat.send'), isEmpty);
  });

  testWidgets('an older runtime sends /feedback as a message', (tester) async {
    final client = await _pump(tester, supported: false);
    client.handlers['agentChat.send'] = (_) => <String, Object?>{
      'delivery': 'started',
    };
    await _send(tester, '/feedback ');
    expect(find.text(agentChatFeedbackConsentTitle), findsNothing);
    expect(client.payloadsOf('agentChat.send').single['text'], '/feedback');
  });
}
