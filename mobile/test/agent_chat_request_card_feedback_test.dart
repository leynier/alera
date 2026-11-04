import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_request_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AgentChatRequest _approval({bool supportsFeedback = true}) =>
    AgentChatRequest.fromJson(<String, Object?>{
      'requestId': 'approval-1',
      'kind': 'permission_approval',
      'createdAt': '2026-10-25T10:00:00Z',
      'title': 'Run git push?',
      'decisions': <Object?>['accept', 'decline', 'cancel'],
      'supportsFeedback': supportsFeedback,
      'fullAccessOverride': 'provider_check',
    });

void main() {
  testWidgets('declines with feedback for the agent that asked', (
    tester,
  ) async {
    final responses = <AgentChatJson>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentChatRequestCard(
            request: _approval(),
            enabled: true,
            onRespond: (_, response) async => responses.add(response.toJson()),
          ),
        ),
      ),
    );

    expect(
      find.text(agentChatFullAccessOverrideMessage(.providerCheck)),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-decline-feedback')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('agentChatDeclineFeedback')),
      'Open a pull request instead.',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('agentChatDeclineFeedbackSend')),
    );
    await tester.pumpAndSettle();
    expect(responses, <AgentChatJson>[
      <String, Object?>{
        'type': 'approval',
        'decision': 'decline',
        'feedback': 'Open a pull request instead.',
      },
    ]);
  });

  testWidgets('offers no feedback when the provider takes none', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentChatRequestCard(
            request: _approval(supportsFeedback: false),
            enabled: true,
            onRespond: (_, _) async {},
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('agent-chat-decline-feedback')),
      findsNothing,
    );
  });
}
