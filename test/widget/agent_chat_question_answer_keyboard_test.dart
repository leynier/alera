import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_question_card.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_request_dock.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final List<AgentChatResponse> _responses = <AgentChatResponse>[];

AgentChatRequest _request(Map<String, Object?> question) =>
    AgentChatRequest.fromJson(<String, Object?>{
      'requestId': 'r1',
      'kind': 'toolUserInput',
      'questions': <Object?>[question],
    });

final AgentChatRequest _withOptions = _request(<String, Object?>{
  'id': 'db',
  'question': 'Which database?',
  'allowCustomAnswer': true,
  'options': <Object?>['Postgres', 'SQLite'],
});

final AgentChatRequest _freeText = _request(<String, Object?>{
  'id': 'branch',
  'question': 'Branch name?',
});

final Finder _answerField = find.descendant(
  of: find.byType(AgentChatRequestDock),
  matching: find.byType(TextField),
);

Map<String, List<String>> get _lastAnswers =>
    (_responses.last as AgentChatUserInputResponse).answers;

Future<void> _pumpDock(WidgetTester tester, AgentChatRequest request) async {
  _responses.clear();
  final composer = TerminalComposerController();
  addTearDown(composer.dispose);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: AgentChatRequestDock(
              chatId: 'chat-1',
              requests: <AgentChatRequest>[request],
              respondingRequestIds: const <String>{},
              enabled: true,
              onRespond: (request, response) async => _responses.add(response),
              composer: composer,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(AgentChatQuestionCard.enterGuard);
}

Future<void> _openCustomAnswer(WidgetTester tester, String text) async {
  await tester.tap(find.text('Write Another Answer'));
  await tester.pump();
  await tester.pump();
  await tester.enterText(_answerField, text);
  await tester.pump();
}

void main() {
  testWidgets(
    'Escape in an opened custom answer closes it and keeps the text',
    (tester) async {
      await _pumpDock(tester, _withOptions);
      await _openCustomAnswer(tester, 'MySQL');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(_responses, isEmpty);
      expect(_answerField, findsNothing);
      expect(find.text('Write Another Answer'), findsOneWidget);

      // The card keeps the keyboard, so the number keys still pick.
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.pump();
      expect(_lastAnswers, <String, List<String>>{
        'db': <String>['SQLite'],
      });
    },
  );

  testWidgets('a second Escape skips the request', (tester) async {
    await _pumpDock(tester, _withOptions);
    await _openCustomAnswer(tester, 'MySQL');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(_responses, hasLength(1));
    expect(_lastAnswers, isEmpty);
  });

  testWidgets('reopening the custom answer brings back what was typed', (
    tester,
  ) async {
    await _pumpDock(tester, _withOptions);
    await _openCustomAnswer(tester, 'MySQL');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    await tester.tap(find.text('Write Another Answer'));
    await tester.pump();
    await tester.pump();
    expect(find.text('MySQL'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(_lastAnswers, <String, List<String>>{
      'db': <String>['MySQL'],
    });
  });

  testWidgets('Escape in the only answer field still skips the request', (
    tester,
  ) async {
    await _pumpDock(tester, _freeText);
    await tester.enterText(_answerField, 'feature/chat');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(_responses, hasLength(1));
    expect(_lastAnswers, isEmpty);
  });

  testWidgets('Enter and Escape stay with the input method while it composes', (
    tester,
  ) async {
    await _pumpDock(tester, _withOptions);
    await _openCustomAnswer(tester, '');
    final controller = tester.widget<TextField>(_answerField).controller!;
    const composing = TextEditingValue(
      text: 'にほん',
      selection: TextSelection.collapsed(offset: 3),
      composing: TextRange(start: 0, end: 3),
    );
    controller.value = composing;
    await tester.pump();

    for (final key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.numpadEnter,
      LogicalKeyboardKey.escape,
    ]) {
      expect(await tester.sendKeyEvent(key), isFalse, reason: '$key');
    }
    // An unhandled key is what the embedder hands to the input method, so
    // a modified Enter must not be consumed either.
    for (final modifier in <LogicalKeyboardKey>[
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.shiftLeft,
    ]) {
      await tester.sendKeyDownEvent(modifier);
      final handled = await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(modifier);
      expect(handled, isFalse, reason: '$modifier+Enter');
    }
    await tester.pump();

    expect(_responses, isEmpty);
    expect(controller.value, composing);
    expect(_answerField, findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  for (final modifier in <LogicalKeyboardKey>[
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.controlLeft,
  ]) {
    testWidgets('${modifier.keyLabel}+Enter sends a committed answer', (
      tester,
    ) async {
      await _pumpDock(tester, _withOptions);
      await _openCustomAnswer(tester, 'MySQL');

      await tester.sendKeyDownEvent(modifier);
      final handled = await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(modifier);
      await tester.pump();

      expect(handled, isTrue);
      expect(_lastAnswers, <String, List<String>>{
        'db': <String>['MySQL'],
      });
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }
}
