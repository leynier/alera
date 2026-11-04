import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_request_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('an option preview opens in a sheet without answering', (
    tester,
  ) async {
    final responses = <AgentChatResponse>[];
    final request = AgentChatRequest.fromJson(<String, Object?>{
      'requestId': 'question-1',
      'kind': 'tool_user_input',
      'createdAt': '2026-10-12T10:00:00Z',
      'questions': <Object?>[
        <String, Object?>{
          'id': 'approach',
          'header': 'Approach',
          'question': 'Which approach?',
          'options': <Object?>[
            <String, Object?>{
              'label': 'Small',
              'preview': 'Patch only the parser',
            },
            <String, Object?>{'label': 'Large'},
          ],
        },
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentChatRequestDock(
            requests: <AgentChatRequest>[request],
            enabled: true,
            respondingRequestIds: const <String>{},
            onRespond: (_, response) async => responses.add(response),
            typing: AgentChatTypingClock(),
          ),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('agent-chat-question-preview-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('agent-chat-question-preview-2')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('agent-chat-question-preview-1')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Patch only the parser'), findsOneWidget);
    expect(responses, isEmpty);
  });
}
