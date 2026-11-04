import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_request_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AgentChatRequest _question() => AgentChatRequest.fromJson(<String, Object?>{
  'requestId': 'question-1',
  'kind': 'tool_user_input',
  'createdAt': '2026-10-12T10:00:00Z',
  'questions': <Object?>[
    <String, Object?>{
      'id': 'target',
      'header': 'Deploy target',
      'question': 'Where should this go?',
      'options': <Object?>[
        <String, Object?>{'label': 'Staging'},
      ],
    },
  ],
});

AgentChatRequest _approval() => AgentChatRequest.fromJson(<String, Object?>{
  'requestId': 'approval-1',
  'kind': 'command_execution_approval',
  'createdAt': '2026-10-12T10:00:05Z',
  'command': 'make deploy',
  'decisions': <Object?>['accept', 'decline'],
});

Widget _dock(List<AgentChatRequest> requests, AgentChatTypingClock typing) =>
    MaterialApp(
      home: Scaffold(
        body: AgentChatRequestDock(
          requests: agentChatRequestDockOrder(requests),
          enabled: true,
          respondingRequestIds: const <String>{},
          onRespond: (_, _) async {},
          typing: typing,
        ),
      ),
    );

void main() {
  testWidgets('an approval waits while the person is typing', (tester) async {
    final typing = AgentChatTypingClock();
    await tester.pumpWidget(_dock(<AgentChatRequest>[_question()], typing));
    expect(find.text('Deploy target'), findsOneWidget);

    typing.keystroke();
    await tester.pumpWidget(
      _dock(<AgentChatRequest>[_question(), _approval()], typing),
    );
    // The page the person is on stays put mid-sentence.
    expect(find.text('Deploy target'), findsOneWidget);
    expect(find.text('Request 2 of 2'), findsOneWidget);

    await tester.pump(agentChatTypingIdle);
    await tester.pump();
    expect(find.text('Run Command?'), findsOneWidget);
    expect(find.text('Request 1 of 2'), findsOneWidget);
  });

  testWidgets('an approval takes the dock at once when nobody types', (
    tester,
  ) async {
    final typing = AgentChatTypingClock();
    await tester.pumpWidget(_dock(<AgentChatRequest>[_question()], typing));
    await tester.pumpWidget(
      _dock(<AgentChatRequest>[_question(), _approval()], typing),
    );
    expect(find.text('Run Command?'), findsOneWidget);
  });
}
