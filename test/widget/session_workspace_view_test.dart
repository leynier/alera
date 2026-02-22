import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';
import 'package:alera/src/features/session/presentation/session_workspace_view.dart';
import 'package:alera/src/shared/models/contracts.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

TimelineCell _cell({
  required String id,
  required TimelineCellKind kind,
  required TimelineCellStatus status,
  String? turnId,
  String? markdownText,
  String? detailsText,
  String? title,
  String? subtitle,
  Map<String, dynamic> metadata = const <String, dynamic>{},
  bool isStreaming = false,
  bool isCollapsed = false,
}) {
  final now = DateTime.utc(2026, 2, 22);
  return TimelineCell(
    id: id,
    turnId: turnId,
    kind: kind,
    status: status,
    createdAt: now,
    updatedAt: now,
    markdownText: markdownText,
    detailsText: detailsText,
    title: title,
    subtitle: subtitle,
    metadata: metadata,
    isStreaming: isStreaming,
    isCollapsed: isCollapsed,
  );
}

Future<void> _pumpWorkspace(
  WidgetTester tester, {
  required SessionState state,
  bool rawLogExpanded = false,
  ValueChanged<String>? onSendInput,
  ValueChanged<String>? onModelChanged,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SessionWorkspaceView(
          state: state,
          onSendInput: onSendInput ?? (_) {},
          onModelChanged: onModelChanged ?? (_) {},
          rawLogExpanded: rawLogExpanded,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  SessionState stateWithActiveSession({
    List<TimelineCell> timeline = const [],
  }) {
    final now = DateTime.utc(2026, 2, 22);
    final session = AleraSession(
      id: 'session-1',
      request: const SessionCreateRequest(
        projectPath: '/repo',
        firstPrompt: 'hello',
        model: 'gpt-5.3-codex',
      ),
      workspacePath: '/repo',
      createdAt: now,
      updatedAt: now,
      title: 'session',
      model: 'gpt-5.3-codex',
    );
    return SessionState(
      sessions: <AleraSession>[session],
      activeSessionId: session.id,
      timelineCells: timeline,
    );
  }

  testWidgets(
    'shows worked for collapsed and final message for completed turn',
    (tester) async {
      final state = SessionState(
        timelineCells: <TimelineCell>[
          _cell(
            id: 'u1',
            kind: TimelineCellKind.userMessage,
            status: TimelineCellStatus.completed,
            turnId: 't1',
            markdownText: 'hello',
          ),
          _cell(
            id: 'reason1',
            kind: TimelineCellKind.reasoning,
            status: TimelineCellStatus.completed,
            turnId: 't1',
            title: 'Thinking',
            markdownText: 'Reasoning detail text',
            isCollapsed: true,
          ),
          _cell(
            id: 'a1',
            kind: TimelineCellKind.assistantMessage,
            status: TimelineCellStatus.completed,
            turnId: 't1',
            markdownText: 'final answer',
          ),
          _cell(
            id: 'sep1',
            kind: TimelineCellKind.turnSeparator,
            status: TimelineCellStatus.completed,
            turnId: 't1',
            metadata: const <String, dynamic>{'durationMs': 293000},
          ),
        ],
      );

      await _pumpWorkspace(tester, state: state);

      expect(find.text('hello'), findsOneWidget);
      expect(find.text('final answer'), findsOneWidget);
      expect(find.textContaining('Worked for'), findsOneWidget);
      expect(find.text('Final message'), findsNothing);
      expect(find.text('Thinking'), findsNothing);
      expect(find.text('Reasoning detail text'), findsNothing);
    },
  );

  testWidgets('turn without secondary items does not show worked for', (
    tester,
  ) async {
    final state = SessionState(
      timelineCells: <TimelineCell>[
        _cell(
          id: 'u1',
          kind: TimelineCellKind.userMessage,
          status: TimelineCellStatus.completed,
          turnId: 't1',
          markdownText: 'hello',
        ),
        _cell(
          id: 'a1',
          kind: TimelineCellKind.assistantMessage,
          status: TimelineCellStatus.completed,
          turnId: 't1',
          markdownText: 'done',
        ),
        _cell(
          id: 'sep1',
          kind: TimelineCellKind.turnSeparator,
          status: TimelineCellStatus.completed,
          turnId: 't1',
          metadata: const <String, dynamic>{'durationMs': 1200},
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state);

    expect(find.text('Final message'), findsNothing);
    expect(find.text('done'), findsOneWidget);
    expect(find.textContaining('Worked for'), findsNothing);
  });

  testWidgets(
    'expanding worked for shows secondary cells and manual toggles do not accordion',
    (tester) async {
      final state = SessionState(
        timelineCells: <TimelineCell>[
          _cell(
            id: 'u1',
            kind: TimelineCellKind.userMessage,
            status: TimelineCellStatus.completed,
            turnId: 't1',
            markdownText: 'hello',
          ),
          _cell(
            id: 'reason1',
            kind: TimelineCellKind.reasoning,
            status: TimelineCellStatus.completed,
            turnId: 't1',
            title: 'Thinking',
            markdownText: 'Reasoning detail text',
            isCollapsed: true,
          ),
          _cell(
            id: 'tool1',
            kind: TimelineCellKind.toolCall,
            status: TimelineCellStatus.completed,
            turnId: 't1',
            title: 'git diff',
            detailsText: 'diff --git a b',
            isCollapsed: true,
          ),
          _cell(
            id: 'a1',
            kind: TimelineCellKind.assistantMessage,
            status: TimelineCellStatus.completed,
            turnId: 't1',
            markdownText: 'done',
          ),
          _cell(
            id: 'sep1',
            kind: TimelineCellKind.turnSeparator,
            status: TimelineCellStatus.completed,
            turnId: 't1',
            metadata: const <String, dynamic>{'durationMs': 1200},
          ),
        ],
      );

      await _pumpWorkspace(tester, state: state);

      expect(find.text('Reasoning detail text'), findsNothing);
      expect(find.text('diff --git a b'), findsNothing);
      expect(find.text('Thinking'), findsNothing);
      expect(find.text('git diff'), findsNothing);
      expect(find.text('Final message'), findsNothing);

      await tester.tap(find.textContaining('Worked for'));
      await tester.pumpAndSettle();
      expect(find.text('Thinking'), findsOneWidget);
      expect(find.text('git diff'), findsOneWidget);
      expect(find.text('Final message'), findsOneWidget);

      await tester.tap(find.text('Thinking'));
      await tester.pumpAndSettle();
      expect(find.text('Reasoning detail text'), findsOneWidget);

      await tester.tap(find.text('git diff'));
      await tester.pumpAndSettle();
      expect(find.text('Reasoning detail text'), findsOneWidget);
      expect(find.text('diff --git a b'), findsOneWidget);
    },
  );

  testWidgets('raw log footer stays collapsable', (tester) async {
    final state = SessionState(
      activityLog: const <String>['event one', 'event two'],
    );

    await _pumpWorkspace(tester, state: state, rawLogExpanded: false);
    expect(find.text('event one'), findsNothing);

    await _pumpWorkspace(tester, state: state, rawLogExpanded: true);
    expect(find.text('event two'), findsOneWidget);
    expect(find.textContaining('event one'), findsOneWidget);
  });

  testWidgets('worked for label renders minutes and seconds', (tester) async {
    final state = SessionState(
      timelineCells: <TimelineCell>[
        _cell(
          id: 'reason-ms',
          kind: TimelineCellKind.reasoning,
          status: TimelineCellStatus.completed,
          turnId: 'turn-ms',
          title: 'Thinking',
          markdownText: 'detail',
          isCollapsed: true,
        ),
        _cell(
          id: 'assistant-ms',
          kind: TimelineCellKind.assistantMessage,
          status: TimelineCellStatus.completed,
          turnId: 'turn-ms',
          markdownText: 'done',
        ),
        _cell(
          id: 'sep-ms',
          kind: TimelineCellKind.turnSeparator,
          status: TimelineCellStatus.completed,
          turnId: 'turn-ms',
          metadata: const <String, dynamic>{'durationMs': 80000},
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state);
    expect(find.text('Worked for 1m 20s'), findsOneWidget);
  });

  testWidgets('worked for label renders days and hours', (tester) async {
    final state = SessionState(
      timelineCells: <TimelineCell>[
        _cell(
          id: 'reason-day',
          kind: TimelineCellKind.reasoning,
          status: TimelineCellStatus.completed,
          turnId: 'turn-day',
          title: 'Thinking',
          markdownText: 'detail',
          isCollapsed: true,
        ),
        _cell(
          id: 'assistant-day',
          kind: TimelineCellKind.assistantMessage,
          status: TimelineCellStatus.completed,
          turnId: 'turn-day',
          markdownText: 'done',
        ),
        _cell(
          id: 'sep-day',
          kind: TimelineCellKind.turnSeparator,
          status: TimelineCellStatus.completed,
          turnId: 'turn-day',
          metadata: const <String, dynamic>{'durationMs': 90061000},
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state);
    expect(find.text('Worked for 1d 1h'), findsOneWidget);
  });

  testWidgets('pressing Enter sends the message', (tester) async {
    var sentCount = 0;
    String? lastMessage;

    await _pumpWorkspace(
      tester,
      state: stateWithActiveSession(),
      onSendInput: (value) {
        sentCount += 1;
        lastMessage = value;
      },
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'hello world');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(sentCount, 1);
    expect(lastMessage, 'hello world');
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.controller.text, isEmpty);
  });

  testWidgets('pressing Shift+Enter inserts newline without sending', (
    tester,
  ) async {
    var sentCount = 0;

    await _pumpWorkspace(
      tester,
      state: stateWithActiveSession(),
      onSendInput: (_) => sentCount += 1,
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(sentCount, 0);
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.controller.text, 'hello\n');
  });

  testWidgets('reasoning chevron appears on hover and hides on exit', (
    tester,
  ) async {
    final state = SessionState(
      timelineCells: <TimelineCell>[
        _cell(
          id: 'reason1',
          kind: TimelineCellKind.reasoning,
          status: TimelineCellStatus.completed,
          turnId: 't1',
          title:
              'Thinking very long line that should truncate before the chevron appears',
          markdownText: 'detail',
          isCollapsed: true,
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state);
    final rowFinder = find.textContaining('Thinking very long line');
    expect(rowFinder, findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(rowFinder));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.keyboard_arrow_right), findsOneWidget);

    await mouse.moveTo(const Offset(0, 0));
    await tester.pumpAndSettle();

    final iconFinder = find.byIcon(Icons.keyboard_arrow_right);
    expect(iconFinder, findsOneWidget);
    final opacityWidget = tester.widget<AnimatedOpacity>(
      find.ancestor(of: iconFinder, matching: find.byType(AnimatedOpacity)),
    );
    expect(opacityWidget.opacity, 0);
  });
}
