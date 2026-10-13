import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_question_card.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_question_dock.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

AgentChatRequest _request(String id, List<Object?> questions) =>
    AgentChatRequest.fromJson(<String, Object?>{
      'requestId': id,
      'kind': 'toolUserInput',
      'questions': questions,
    });

final class _Responses {
  final List<(AgentChatRequest, AgentChatResponse)> calls =
      <(AgentChatRequest, AgentChatResponse)>[];

  Future<void> call(AgentChatRequest request, AgentChatResponse response) {
    calls.add((request, response));
    return Future<void>.value();
  }

  Map<String, List<String>> get lastAnswers =>
      (calls.last.$2 as AgentChatUserInputResponse).answers;
}

const Key _composerKey = ValueKey<String>('composer');

final Finder _answerField = find.descendant(
  of: find.byType(AgentChatQuestionDock),
  matching: find.byType(TextField),
);

/// The dock above a stand-in composer, which stays mounted as it does in the
/// chat footer.
Widget _dock({
  required List<AgentChatRequest> requests,
  required _Responses responses,
  Set<String> responding = const <String>{},
  bool enabled = true,
}) {
  return MaterialApp(
    theme: buildAleraDarkTheme(),
    home: Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          AgentChatQuestionDock(
            chatId: 'chat-1',
            requests: requests,
            respondingRequestIds: responding,
            enabled: enabled,
            onRespond: responses.call,
          ),
          const TextField(key: _composerKey),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('a single choice advances and the last one sends answer values', (
    tester,
  ) async {
    final responses = _Responses();
    final request = _request('r1', <Object?>[
      <String, Object?>{
        'id': 'db',
        'header': 'Database',
        'question': 'Which database should the service use?',
        'options': <Object?>[
          <String, Object?>{
            'label': 'Postgres',
            'description': 'Managed cluster',
            'value': 'postgresql',
          },
          'SQLite',
        ],
      },
      <String, Object?>{
        'id': 'seed',
        'question': 'Seed sample data?',
        'options': <Object?>['Yes', 'No'],
      },
    ]);
    await tester.pumpWidget(_dock(requests: [request], responses: responses));

    expect(find.text('Database'), findsOneWidget);
    expect(find.text('Managed cluster'), findsOneWidget);
    expect(find.text('1 of 2'), findsOneWidget);
    expect(find.text('Write Another Answer'), findsNothing);

    await tester.tap(find.text('Postgres'));
    await tester.pump();

    expect(responses.calls, isEmpty);
    expect(find.text('Seed sample data?'), findsOneWidget);
    expect(find.text('2 of 2'), findsOneWidget);

    await tester.tap(find.text('No'));
    await tester.pump();

    expect(responses.calls, hasLength(1));
    expect(responses.calls.single.$1.id, 'r1');
    expect(responses.lastAnswers, <String, List<String>>{
      'db': <String>['postgresql'],
      'seed': <String>['No'],
    });
  });

  testWidgets('a multi select sends the picked options and the typed answer', (
    tester,
  ) async {
    final responses = _Responses();
    final request = _request('r1', <Object?>[
      <String, Object?>{
        'id': 'langs',
        'question': 'Which languages?',
        'multiSelect': true,
        'allowCustomAnswer': true,
        'options': <Object?>['Dart', 'Rust', 'Go'],
      },
    ]);
    await tester.pumpWidget(_dock(requests: [request], responses: responses));

    final submit = find.widgetWithText(FilledButton, 'Submit');
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.tap(find.text('Go'));
    await tester.tap(find.text('Dart'));
    await tester.tap(find.text('Rust'));
    await tester.tap(find.text('Rust'));
    await tester.pump();
    expect(responses.calls, isEmpty);

    await tester.tap(find.text('Write Another Answer'));
    await tester.pump();
    await tester.enterText(_answerField, '  Zig  ');
    await tester.pump();
    await tester.tap(submit);
    await tester.pump();

    expect(responses.lastAnswers, <String, List<String>>{
      'langs': <String>['Dart', 'Go', 'Zig'],
    });
  });

  testWidgets('Skip and Escape answer the whole request with no answers', (
    tester,
  ) async {
    final responses = _Responses();
    final request = _request('r1', <Object?>[
      <String, Object?>{
        'id': 'q1',
        'question': 'First?',
        'options': <Object?>['A', 'B'],
      },
      <String, Object?>{'id': 'q2', 'question': 'Second?'},
    ]);
    await tester.pumpWidget(_dock(requests: [request], responses: responses));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Skip'));
    await tester.pump();
    expect(responses.calls, hasLength(1));
    expect(responses.lastAnswers, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(responses.calls, hasLength(2));
    expect(responses.lastAnswers, isEmpty);
  });

  testWidgets('paging between requests keeps the first request draft', (
    tester,
  ) async {
    final responses = _Responses();
    final first = _request('r1', <Object?>[
      <String, Object?>{
        'id': 'tools',
        'question': 'Which checks should run?',
        'multiSelect': true,
        'options': <Object?>['Lint', 'Format'],
      },
      <String, Object?>{'id': 'note', 'question': 'Anything else?'},
    ]);
    final second = _request('r2', <Object?>[
      <String, Object?>{
        'id': 'other',
        'question': 'Ship it?',
        'options': <Object?>['Yes', 'No'],
      },
    ]);
    await tester.pumpWidget(
      _dock(requests: [first, second], responses: responses),
    );
    expect(find.text('Request 1 of 2'), findsOneWidget);

    await tester.tap(find.text('Format'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump();
    await tester.enterText(_answerField, 'Keep the lockfile');
    await tester.pump();

    await tester.tap(find.byTooltip('Next Request'));
    await tester.pump();
    expect(find.text('Request 2 of 2'), findsOneWidget);
    expect(find.text('Ship it?'), findsOneWidget);
    expect(_answerField, findsNothing);

    await tester.tap(find.byTooltip('Previous Request'));
    await tester.pump();
    expect(find.text('Anything else?'), findsOneWidget);
    expect(find.text('Keep the lockfile'), findsOneWidget);

    await tester.tap(find.byTooltip('Previous Question'));
    await tester.pump();
    expect(
      find.descendant(
        of: find.widgetWithText(FilledButton, 'Continue'),
        matching: find.text('Continue'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Next Question'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pump();

    expect(responses.calls.single.$1.id, 'r1');
    expect(responses.lastAnswers, <String, List<String>>{
      'tools': <String>['Format'],
      'note': <String>['Keep the lockfile'],
    });
  });

  testWidgets('the active request stays put and falls to its neighbor', (
    tester,
  ) async {
    final responses = _Responses();
    AgentChatRequest single(String id, String question) =>
        _request(id, <Object?>[
          <String, Object?>{
            'id': 'q',
            'question': question,
            'options': <Object?>['Yes', 'No'],
          },
        ]);
    final r0 = single('r0', 'Zeroth?');
    final r1 = single('r1', 'First?');
    final r2 = single('r2', 'Second?');
    final r3 = single('r3', 'Third?');
    await tester.pumpWidget(
      _dock(requests: [r1, r2, r3], responses: responses),
    );
    await tester.tap(find.byTooltip('Next Request'));
    await tester.pump();
    expect(find.text('Second?'), findsOneWidget);

    await tester.pumpWidget(
      _dock(requests: [r0, r1, r2, r3], responses: responses),
    );
    expect(find.text('Second?'), findsOneWidget);
    expect(find.text('Request 3 of 4'), findsOneWidget);

    await tester.pumpWidget(
      _dock(requests: [r0, r1, r3], responses: responses),
    );
    expect(find.text('Third?'), findsOneWidget);
    expect(find.text('Request 3 of 3'), findsOneWidget);

    await tester.pumpWidget(_dock(requests: [r0, r1], responses: responses));
    expect(find.text('First?'), findsOneWidget);
    expect(find.text('Request 2 of 2'), findsOneWidget);
  });

  testWidgets('a request being answered disables its controls', (tester) async {
    final responses = _Responses();
    final request = _request('r1', <Object?>[
      <String, Object?>{
        'id': 'q',
        'question': 'Proceed?',
        'allowCustomAnswer': true,
        'options': <Object?>['Yes', 'No'],
      },
    ]);
    await tester.pumpWidget(
      _dock(
        requests: [request],
        responses: responses,
        responding: const <String>{'r1'},
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Yes'));
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.tap(find.text('Write Another Answer'));
    await tester.pump();

    expect(responses.calls, isEmpty);
    expect(_answerField, findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Skip'))
          .onPressed,
      isNull,
    );

    await tester.pumpWidget(
      _dock(requests: [request], responses: responses, enabled: false),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('No'));
    await tester.pump();
    expect(responses.calls, isEmpty);
  });

  testWidgets('number keys pick the matching option while the card has focus', (
    tester,
  ) async {
    final responses = _Responses();
    final request = _request('r1', <Object?>[
      <String, Object?>{
        'id': 'target',
        'question': 'Deploy where?',
        'options': <Object?>['Staging', 'Production'],
      },
    ]);
    await tester.pumpWidget(_dock(requests: [request], responses: responses));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump();
    expect(responses.calls, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pump();
    expect(responses.lastAnswers, <String, List<String>>{
      'target': <String>['Production'],
    });
  });

  testWidgets('a click takes the keyboard and the next request keeps it', (
    tester,
  ) async {
    final responses = _Responses();
    AgentChatRequest single(String id, List<Object?> options) =>
        _request(id, <Object?>[
          <String, Object?>{
            'id': 'q',
            'question': 'Pick for $id',
            'options': options,
          },
        ]);
    final first = single('r1', <Object?>['A', 'B']);
    final second = single('r2', <Object?>['C', 'D']);
    await tester.pumpWidget(
      _dock(requests: [first, second], responses: responses),
    );
    await tester.tap(find.byKey(_composerKey));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(responses.calls, isEmpty);

    await tester.tap(find.text('Pick for r1'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(responses.calls.single.$1.id, 'r1');

    await tester.pumpWidget(_dock(requests: [second], responses: responses));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pump();
    expect(responses.calls.last.$1.id, 'r2');
    expect(responses.lastAnswers, <String, List<String>>{
      'q': <String>['D'],
    });
  });

  testWidgets('an Enter right after the card appears is ignored', (
    tester,
  ) async {
    final responses = _Responses();
    final request = _request('r1', <Object?>[
      <String, Object?>{
        'id': 'branch',
        'question': 'Branch name?',
        'initialAnswer': 'feature/chat',
      },
    ]);
    await tester.pumpWidget(_dock(requests: [request], responses: responses));
    await tester.pump();
    expect(find.text('feature/chat'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(responses.calls, isEmpty);

    await tester.pump(AgentChatQuestionCard.enterGuard);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(responses.lastAnswers, <String, List<String>>{
      'branch': <String>['feature/chat'],
    });
  });
}
