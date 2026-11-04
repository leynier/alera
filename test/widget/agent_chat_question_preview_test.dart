import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_request_dock.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('an option preview opens on request without answering', (
    tester,
  ) async {
    final composer = TerminalComposerController();
    addTearDown(composer.dispose);
    final responses = <AgentChatResponse>[];
    final request = AgentChatRequest.fromJson(<String, Object?>{
      'requestId': 'r1',
      'kind': 'toolUserInput',
      'questions': <Object?>[
        <String, Object?>{
          'id': 'approach',
          'question': 'Which approach?',
          'options': <Object?>[
            <String, Object?>{
              'label': 'Small',
              'description': 'Patch it',
              'preview': '**Patch** only the parser',
            },
            <String, Object?>{'label': 'Large', 'description': 'Rewrite it'},
          ],
        },
      ],
    });
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: Scaffold(
            body: AgentChatRequestDock(
              chatId: 'chat-1',
              requests: <AgentChatRequest>[request],
              respondingRequestIds: const <String>{},
              enabled: true,
              onRespond: (_, response) async => responses.add(response),
              composer: composer,
            ),
          ),
        ),
      ),
    );
    final toggle = find.byKey(
      const ValueKey<String>('agent-chat-question-preview-toggle'),
    );
    expect(toggle, findsOneWidget);
    expect(find.textContaining('only the parser'), findsNothing);
    await tester.tap(toggle);
    await tester.pump();
    expect(find.textContaining('only the parser'), findsOneWidget);
    expect(find.text('Hide Preview'), findsOneWidget);
    expect(responses, isEmpty);

    await tester.tap(find.text('Small'));
    await tester.pump();
    expect(responses, hasLength(1));
  });
}
