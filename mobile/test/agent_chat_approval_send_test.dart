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

Future<FakeAgentChatClient> _pumpApproval(
  WidgetTester tester, {
  bool feedback = false,
  bool redirects = true,
}) async {
  final client = FakeAgentChatClient(
    capabilities: <String>{
      'agentChatV1',
      if (redirects) AgentChatWire.approvalRedirectCapability,
    },
  );
  client.handlers['agentChat.snapshot'] = (_) => agentChatSnapshot(
    session: agentChatSession(status: 'waiting', activeTurnId: 'turn-1'),
    pendingRequests: <Map<String, Object?>>[
      <String, Object?>{
        'requestId': 'approval-1',
        'kind': 'command_execution_approval',
        'turnId': 'turn-1',
        'createdAt': '2026-10-12T10:00:01Z',
        'command': 'cargo clean',
        'decisions': <String>['accept', 'decline', 'cancel'],
        'supportsFeedback': feedback,
      },
    ],
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

void main() {
  testWidgets('feedback declines the shown approval and clears the draft', (
    tester,
  ) async {
    final client = await _pumpApproval(tester, feedback: true);
    client.handlers['agentChat.respond'] = (_) => <String, Object?>{
      'resolved': true,
    };
    expect(find.text(agentChatApprovalFeedbackHint), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Keep the build cache.');
    await tester.pump();
    await tester.tap(find.byTooltip(agentChatApprovalFeedbackSendLabel));
    await tester.pumpAndSettle();
    expect(
      client.payloadsOf('agentChat.respond').single['response'],
      <String, Object?>{
        'type': 'approval',
        'decision': 'decline',
        'feedback': 'Keep the build cache.',
      },
    );
    expect(client.payloadsOf('agentChat.send'), isEmpty);
    expect(_composerText(tester), '');
  });

  testWidgets('a redirect declines and sends in one request', (tester) async {
    final client = await _pumpApproval(tester);
    client.handlers['agentChat.send'] = (_) => <String, Object?>{
      'delivery': 'queued',
      'queueId': 'queue-1',
    };
    expect(find.text(agentChatApprovalRedirectHint), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Run the tests instead.');
    await tester.pump();
    await tester.tap(find.byTooltip(agentChatApprovalRedirectSendLabel));
    await tester.pumpAndSettle();
    final payload = client.payloadsOf('agentChat.send').single;
    expect(payload['text'], 'Run the tests instead.');
    expect(payload['declineRequests'], <String, Object?>{
      'requestIds': <String>['approval-1'],
    });
    expect(client.payloadsOf('agentChat.respond'), isEmpty);
    expect(_composerText(tester), '');
  });

  testWidgets('a refused redirect keeps the draft and says why', (
    tester,
  ) async {
    final client = await _pumpApproval(tester);
    client.handlers['agentChat.send'] = (_) => throw RuntimeRequestError(
      "Another approval arrived, so your message wasn't sent.",
      code: AgentChatErrorCodes.approvalsChanged,
    );
    await tester.enterText(find.byType(TextField), 'Run the tests instead.');
    await tester.pump();
    await tester.tap(find.byTooltip(agentChatApprovalRedirectSendLabel));
    await tester.pumpAndSettle();
    expect(
      find.text("Another approval arrived, so your message wasn't sent."),
      findsOneWidget,
    );
    expect(_composerText(tester), 'Run the tests instead.');
  });

  testWidgets('an older runtime declines first, then sends', (tester) async {
    final client = await _pumpApproval(tester, redirects: false);
    client.handlers['agentChat.respond'] = (_) => <String, Object?>{
      'resolved': true,
    };
    client.handlers['agentChat.send'] = (_) => <String, Object?>{
      'delivery': 'queued',
      'queueId': 'queue-1',
    };
    await tester.enterText(find.byType(TextField), 'Run the tests instead.');
    await tester.pump();
    await tester.tap(find.byTooltip(agentChatApprovalRedirectSendLabel));
    await tester.pumpAndSettle();
    expect(
      client.payloadsOf('agentChat.respond').single['response'],
      <String, Object?>{'type': 'approval', 'decision': 'decline'},
    );
    final payload = client.payloadsOf('agentChat.send').single;
    expect(payload.containsKey('declineRequests'), isFalse);
    expect(_composerText(tester), '');
  });
}
