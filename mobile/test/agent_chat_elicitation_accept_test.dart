import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_request_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AgentChatRequest _elicitation(Map<String, Object?> schema) =>
    AgentChatRequest.fromJson(<String, Object?>{
      'requestId': 'elicit-1',
      'kind': 'mcp_elicitation_approval',
      'createdAt': '2026-10-12T10:00:00Z',
      'title': 'GitHub needs input',
      'elicitation': <String, Object?>{
        'mode': 'form',
        'message': 'Pick a reviewer',
        'schema': schema,
      },
    });

Future<void> _pump(WidgetTester tester, AgentChatRequest request) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AgentChatRequestDock(
              requests: <AgentChatRequest>[request],
              enabled: true,
              respondingRequestIds: const <String>{},
              onRespond: (_, _) async {},
              typing: AgentChatTypingClock(),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('a confirmation offers Accept', (tester) async {
    await _pump(tester, _elicitation(<String, Object?>{'properties': {}}));
    expect(find.widgetWithText(FilledButton, 'Accept'), findsOneWidget);
  });

  testWidgets('a form the phone cannot fill offers no Accept', (tester) async {
    await _pump(
      tester,
      _elicitation(<String, Object?>{
        'properties': <String, Object?>{
          'reviewers': <String, Object?>{'type': 'array'},
        },
      }),
    );
    expect(find.widgetWithText(FilledButton, 'Accept'), findsNothing);
    expect(find.text('This request cannot be filled in here.'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
  });
}
