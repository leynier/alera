import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_request_dock.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AgentChatRequest _approval(
  String id, {
  String createdAt = '2026-10-12T10:00:00Z',
}) => AgentChatRequest.fromJson(<String, Object?>{
  'requestId': id,
  'kind': 'commandExecutionApproval',
  'createdAt': createdAt,
  'command': 'make $id',
  'decisions': <Object?>['accept', 'acceptForSession', 'decline', 'cancel'],
});

AgentChatRequest _question(String id) =>
    AgentChatRequest.fromJson(<String, Object?>{
      'requestId': id,
      'kind': 'toolUserInput',
      'createdAt': '2026-10-12T09:00:00Z',
      'questions': <Object?>[
        <String, Object?>{
          'id': 'q',
          'question': 'Pick for $id',
          'options': <Object?>['A', 'B'],
        },
      ],
    });

const Key _composerKey = ValueKey<String>('composer');

final class _Harness {
  final TerminalComposerController composer = TerminalComposerController();
  final List<(AgentChatRequest, AgentChatResponse)> responses =
      <(AgentChatRequest, AgentChatResponse)>[];

  /// The typing guard reads this clock; [advance] moves it with fake time.
  DateTime now = DateTime.utc(2026, 10, 12, 10);

  late final ProviderContainer container = ProviderContainer(
    overrides: [agentChatClockProvider.overrideWithValue(() => now)],
  );

  Future<void> advance(WidgetTester tester, Duration duration) async {
    now = now.add(duration);
    await tester.pump(duration);
  }

  Widget build(List<AgentChatRequest> requests, {bool showDock = true}) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: Scaffold(
            body: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                if (showDock)
                  AgentChatRequestDock(
                    chatId: 'chat-1',
                    requests: agentChatRequestDockOrder(requests),
                    respondingRequestIds: const <String>{},
                    enabled: true,
                    composer: composer,
                    onRespond: (request, response) async =>
                        responses.add((request, response)),
                  ),
                TextField(
                  key: _composerKey,
                  controller: composer.textController,
                  focusNode: composer.focusNode,
                ),
              ],
            ),
          ),
        ),
      );
}

void main() {
  late _Harness harness;
  setUp(() => harness = _Harness());
  tearDown(() {
    harness.composer.dispose();
    harness.container.dispose();
  });

  testWidgets('approvals dock ahead of questions with request paging', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness.build(<AgentChatRequest>[_question('q1'), _approval('a1')]),
    );
    await tester.pump();
    expect(find.text('Request 1 of 2'), findsOneWidget);
    expect(find.text('Run Command?'), findsOneWidget);
    expect(find.text('make a1'), findsOneWidget);

    await tester.tap(find.byTooltip('Next Request'));
    await tester.pump();
    expect(find.text('Request 2 of 2'), findsOneWidget);
    expect(find.text('Pick for q1'), findsOneWidget);
  });

  testWidgets('an approval offers exactly the runtime decisions', (
    tester,
  ) async {
    await tester.pumpWidget(harness.build(<AgentChatRequest>[_approval('a1')]));
    await tester.pump();
    expect(find.widgetWithText(FilledButton, 'Allow Once'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Decline'), findsOneWidget);
    await tester.tap(find.byTooltip('More Decisions'));
    await tester.pumpAndSettle();
    expect(find.text('Allow For Session'), findsOneWidget);
    expect(find.text('Cancel Turn'), findsOneWidget);
    expect(find.text('Always Allow'), findsNothing);
  });

  testWidgets('a request arriving mid-sentence leaves the caret and draft', (
    tester,
  ) async {
    await tester.pumpWidget(harness.build(const <AgentChatRequest>[]));
    await tester.tap(find.byKey(_composerKey));
    await tester.enterText(find.byKey(_composerKey), 'half a thou');
    await tester.pump();

    await tester.pumpWidget(harness.build(<AgentChatRequest>[_approval('a1')]));
    await tester.pump();
    expect(harness.composer.focusNode.hasFocus, isTrue);

    // Typing keeps the takeover held.
    await harness.advance(tester, const Duration(milliseconds: 1000));
    await tester.enterText(find.byKey(_composerKey), 'half a thought');
    await harness.advance(tester, const Duration(milliseconds: 1000));
    expect(harness.composer.focusNode.hasFocus, isTrue);

    // A pause releases it; the draft stays.
    await harness.advance(tester, agentChatTypingIdle);
    await tester.pump();
    expect(harness.composer.focusNode.hasFocus, isFalse);
    expect(harness.composer.textController.text, 'half a thought');
    expect(harness.responses, isEmpty);
  });

  testWidgets('an idle composer hands the keyboard to a new request', (
    tester,
  ) async {
    await tester.pumpWidget(harness.build(const <AgentChatRequest>[]));
    await tester.tap(find.byKey(_composerKey));
    await tester.pump();

    await tester.pumpWidget(harness.build(<AgentChatRequest>[_question('q1')]));
    await tester.pump();
    await tester.pump();
    expect(harness.composer.focusNode.hasFocus, isFalse);

    // Past the card's Enter guard, a digit picks the option.
    await harness.advance(tester, const Duration(milliseconds: 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pump();
    expect(
      (harness.responses.single.$2 as AgentChatUserInputResponse).answers,
      <String, List<String>>{
        'q': <String>['B'],
      },
    );
  });

  testWidgets('a dock that mounts with its request waits for a pause', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness.build(const <AgentChatRequest>[], showDock: false),
    );
    await tester.tap(find.byKey(_composerKey));
    await tester.enterText(find.byKey(_composerKey), 'typing');
    await tester.pump();

    // The footer mounts the dock only once a request exists, so the dock
    // never saw that keystroke.
    await tester.pumpWidget(harness.build(<AgentChatRequest>[_approval('a1')]));
    await tester.pump();
    expect(harness.composer.focusNode.hasFocus, isTrue);

    await harness.advance(tester, agentChatTypingIdle);
    await tester.pump();
    expect(harness.composer.focusNode.hasFocus, isFalse);
    expect(harness.composer.textController.text, 'typing');
  });

  testWidgets('no key decides an approval; Escape returns to the composer', (
    tester,
  ) async {
    await tester.pumpWidget(harness.build(const <AgentChatRequest>[]));
    await tester.tap(find.byKey(_composerKey));
    await tester.pump();
    await tester.pumpWidget(harness.build(<AgentChatRequest>[_approval('a1')]));
    await tester.pump();
    await tester.pump();
    expect(harness.composer.focusNode.hasFocus, isFalse);

    for (final key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.digit1,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }
    expect(harness.responses, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(harness.composer.focusNode.hasFocus, isTrue);
    expect(harness.responses, isEmpty);
  });

  testWidgets('a request already seen does not take the keyboard again', (
    tester,
  ) async {
    await tester.pumpWidget(harness.build(<AgentChatRequest>[_approval('a1')]));
    await tester.pump();
    await tester.tap(find.byKey(_composerKey));
    await tester.pump();

    // A rebuild with the same request, as a tab switch causes, leaves the
    // keyboard in the composer.
    await tester.pumpWidget(harness.build(<AgentChatRequest>[_approval('a1')]));
    await tester.pump();
    await harness.advance(tester, agentChatTypingIdle);
    expect(harness.composer.focusNode.hasFocus, isTrue);
  });
}
