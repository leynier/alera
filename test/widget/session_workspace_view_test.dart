import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/session/application/session_runtime_event.dart';
import 'package:alera/src/features/session/application/session_timeline_reducer.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';
import 'package:alera/src/features/session/domain/pending_message.dart';
import 'package:alera/src/features/session/domain/pending_user_input.dart';
import 'package:alera/src/features/session/presentation/session_workspace_view.dart';
import 'package:alera/src/shared/models/contracts.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_streaming_text_markdown/flutter_streaming_text_markdown.dart';
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

SessionNotificationEvent _event(String method, Map<String, dynamic> params) {
  return SessionNotificationEvent(
    method: method,
    payload: <String, dynamic>{'params': params},
  );
}

Future<void> _pumpWorkspace(
  WidgetTester tester, {
  required SessionState state,
  bool rawLogExpanded = false,
  bool isTurnRunning = false,
  bool isInterrupting = false,
  ValueChanged<String>? onSendInput,
  VoidCallback? onInterruptTurn,
  ValueChanged<String>? onModelChanged,
  ValueChanged<String>? onReasoningEffortChanged,
  List<String>? supportedReasoningEfforts,
  String? activeReasoningEffort,
  VoidCallback? onPlanModeToggled,
  Future<void> Function()? onImplementPlanPressed,
  bool? isMarkdownEnabled,
  ValueChanged<bool>? onMarkdownModeChanged,
  ValueChanged<Map<String, dynamic>>? onSubmitUserInput,
  VoidCallback? onDismissUserInput,
  Duration settleDuration = const Duration(milliseconds: 250),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SessionWorkspaceView(
          state: state,
          onSendInput: onSendInput ?? (_) {},
          onInterruptTurn: onInterruptTurn ?? () {},
          isTurnRunning: isTurnRunning,
          isInterrupting: isInterrupting,
          onModelChanged: onModelChanged ?? (_) {},
          activeReasoningEffort:
              activeReasoningEffort ?? state.activeReasoningEffort,
          supportedReasoningEfforts:
              supportedReasoningEfforts ??
              const <String>['low', 'medium', 'high', 'xhigh'],
          onReasoningEffortChanged: onReasoningEffortChanged ?? (_) {},
          isMarkdownEnabled: isMarkdownEnabled ?? true,
          onMarkdownModeChanged: onMarkdownModeChanged ?? (_) {},
          rawLogExpanded: rawLogExpanded,
          onAddAttachment: () {},
          onRemoveAttachment: (_) {},
          onRemoveFromQueue: (_) {},
          onPlanModeToggled: onPlanModeToggled ?? () {},
          onImplementPlanPressed: onImplementPlanPressed ?? () async {},
          onPermissionModeToggled: () {},
          onApproveRequest: (_, {forSession = false}) async {},
          onDeclineRequest: (_) async {},
          onSubmitUserInput: onSubmitUserInput ?? (_) {},
          onDismissUserInput: onDismissUserInput ?? () {},
        ),
      ),
    ),
  );
  await tester.pump(settleDuration);
}

List<TimelineCell> _longAssistantTimeline({int count = 80}) {
  return List<TimelineCell>.generate(
    count,
    (index) => _cell(
      id: 'assistant-$index',
      kind: TimelineCellKind.assistantMessage,
      status: TimelineCellStatus.completed,
      markdownText: 'assistant line $index',
    ),
  );
}

IconButton _scrollToBottomButton(WidgetTester tester) {
  return tester.widget<IconButton>(
    find.byKey(const ValueKey<String>('scroll-to-bottom-button')),
  );
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

  testWidgets('user input card renders custom other label', (tester) async {
    final state = SessionState(
      pendingUserInput: const PendingUserInput(
        requestId: 'local-plan-fallback-turn-1',
        threadId: 'thread-1',
        turnId: 'turn-1',
        itemId: 'turn-1-local-plan-fallback',
        questions: <UserInputQuestion>[
          UserInputQuestion(
            id: 'implement_plan',
            header: 'Implementation',
            question: 'Implement this plan?',
            isOther: true,
            options: <UserInputOption>[
              UserInputOption(
                label: 'Yes, implement this plan',
                description: 'Proceed with implementation',
              ),
            ],
            otherLabel: 'No, and tell Alera what to do differently',
          ),
        ],
        source: PendingUserInputSource.localPlanFallback,
        localPlanTurnId: 'turn-1',
      ),
    );

    await _pumpWorkspace(tester, state: state);

    expect(find.text('Implement this plan?'), findsOneWidget);
    expect(
      find.text('No, and tell Alera what to do differently'),
      findsOneWidget,
    );
  });

  testWidgets(
    'shows implement plan button when latest plan is newer than latest user message',
    (tester) async {
      final state = stateWithActiveSession(
        timeline: <TimelineCell>[
          _cell(
            id: 'user-1',
            kind: TimelineCellKind.userMessage,
            status: TimelineCellStatus.completed,
            turnId: 'turn-1',
            markdownText: 'plan this work',
          ),
          _cell(
            id: 'plan-1',
            kind: TimelineCellKind.plan,
            status: TimelineCellStatus.completed,
            turnId: 'turn-1',
            markdownText: '1. Implement it',
            isCollapsed: true,
          ),
        ],
      );

      await _pumpWorkspace(tester, state: state);

      expect(
        find.byKey(const ValueKey<String>('implement-plan-button')),
        findsOneWidget,
      );
    },
  );

  testWidgets('implement plan button renders inside timeline container', (
    tester,
  ) async {
    final state = stateWithActiveSession(
      timeline: <TimelineCell>[
        _cell(
          id: 'plan-1',
          kind: TimelineCellKind.plan,
          status: TimelineCellStatus.completed,
          turnId: 'turn-1',
          markdownText: 'plan',
          isCollapsed: true,
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state);

    final buttonFinder = find.byKey(
      const ValueKey<String>('implement-plan-button'),
    );
    expect(buttonFinder, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('timeline-content-container')),
        matching: buttonFinder,
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'implement plan button is rendered in timeline list, not external slot',
    (tester) async {
      final state = stateWithActiveSession(
        timeline: <TimelineCell>[
          _cell(
            id: 'plan-1',
            kind: TimelineCellKind.plan,
            status: TimelineCellStatus.completed,
            turnId: 'turn-1',
            markdownText: 'plan',
            isCollapsed: true,
          ),
        ],
      );

      await _pumpWorkspace(tester, state: state);

      final buttonFinder = find.byKey(
        const ValueKey<String>('implement-plan-button'),
      );
      expect(
        find.ancestor(
          of: buttonFinder,
          matching: find.byKey(const ValueKey<String>('timeline-list')),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('shows implement plan button for collapsed plan', (tester) async {
    final state = stateWithActiveSession(
      timeline: <TimelineCell>[
        _cell(
          id: 'user-1',
          kind: TimelineCellKind.userMessage,
          status: TimelineCellStatus.completed,
          turnId: 'turn-1',
          markdownText: 'build plan',
        ),
        _cell(
          id: 'plan-1',
          kind: TimelineCellKind.plan,
          status: TimelineCellStatus.completed,
          turnId: 'turn-1',
          markdownText: 'collapsed plan details',
          isCollapsed: true,
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state);

    expect(find.text('collapsed plan details'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('implement-plan-button')),
      findsOneWidget,
    );
  });

  testWidgets('shows implement plan button for expanded plan', (tester) async {
    final state = stateWithActiveSession(
      timeline: <TimelineCell>[
        _cell(
          id: 'user-1',
          kind: TimelineCellKind.userMessage,
          status: TimelineCellStatus.completed,
          turnId: 'turn-1',
          markdownText: 'build plan',
        ),
        _cell(
          id: 'plan-1',
          kind: TimelineCellKind.plan,
          status: TimelineCellStatus.completed,
          turnId: 'turn-1',
          markdownText: 'expanded plan details',
          isCollapsed: false,
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state);

    expect(find.text('expanded plan details'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('implement-plan-button')),
      findsOneWidget,
    );
  });

  testWidgets('hides implement plan button when a newer user message exists', (
    tester,
  ) async {
    final state = stateWithActiveSession(
      timeline: <TimelineCell>[
        _cell(
          id: 'plan-1',
          kind: TimelineCellKind.plan,
          status: TimelineCellStatus.completed,
          turnId: 'turn-1',
          markdownText: 'stale plan',
          isCollapsed: true,
        ),
        _cell(
          id: 'user-2',
          kind: TimelineCellKind.userMessage,
          status: TimelineCellStatus.completed,
          turnId: 'turn-2',
          markdownText: 'new user request',
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state);

    expect(
      find.byKey(const ValueKey<String>('implement-plan-button')),
      findsNothing,
    );
  });

  testWidgets(
    'hides implement plan button when pending message queue is not empty',
    (tester) async {
      final state =
          stateWithActiveSession(
            timeline: <TimelineCell>[
              _cell(
                id: 'user-1',
                kind: TimelineCellKind.userMessage,
                status: TimelineCellStatus.completed,
                turnId: 'turn-1',
                markdownText: 'plan this',
              ),
              _cell(
                id: 'plan-1',
                kind: TimelineCellKind.plan,
                status: TimelineCellStatus.completed,
                turnId: 'turn-1',
                markdownText: 'pending queue plan',
                isCollapsed: true,
              ),
            ],
          ).copyWith(
            pendingMessages: const <PendingMessage>[
              PendingMessage(id: 'queued-1', text: 'follow-up'),
            ],
          );

      await _pumpWorkspace(tester, state: state);

      expect(
        find.byKey(const ValueKey<String>('implement-plan-button')),
        findsNothing,
      );
    },
  );

  testWidgets('tap implement plan triggers dedicated callback', (tester) async {
    final calls = <String>[];
    final state = stateWithActiveSession(
      timeline: <TimelineCell>[
        _cell(
          id: 'plan-1',
          kind: TimelineCellKind.plan,
          status: TimelineCellStatus.completed,
          turnId: 'turn-1',
          markdownText: 'plan',
          isCollapsed: true,
        ),
      ],
    );

    await _pumpWorkspace(
      tester,
      state: state,
      onPlanModeToggled: () => calls.add('toggle'),
      onSendInput: (value) => calls.add('send:$value'),
      onImplementPlanPressed: () async => calls.add('implement'),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('implement-plan-button')),
    );
    await tester.pump();

    expect(calls, <String>['implement']);
  });

  testWidgets('backend user input card and implement plan button can coexist', (
    tester,
  ) async {
    final state =
        stateWithActiveSession(
          timeline: <TimelineCell>[
            _cell(
              id: 'plan-1',
              kind: TimelineCellKind.plan,
              status: TimelineCellStatus.completed,
              turnId: 'turn-1',
              markdownText: 'plan',
              isCollapsed: true,
            ),
          ],
        ).copyWith(
          pendingUserInput: const PendingUserInput(
            requestId: 42,
            threadId: 'thread-1',
            turnId: 'turn-1',
            itemId: 'item-user-input',
            questions: <UserInputQuestion>[
              UserInputQuestion(
                id: 'implement_now',
                header: 'Implementation',
                question: 'Implement this plan now?',
              ),
            ],
          ),
        );

    await _pumpWorkspace(tester, state: state);

    expect(
      find.byKey(const ValueKey<String>('implement-plan-button')),
      findsOneWidget,
    );
    expect(find.text('Implement this plan now?'), findsOneWidget);
  });

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
            id: 'tool1',
            kind: TimelineCellKind.toolCall,
            status: TimelineCellStatus.completed,
            turnId: 't1',
            title: 'Ran git status',
            detailsText: 'On branch main',
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
      expect(
        find.byKey(const ValueKey<String>('worked-divider')),
        findsOneWidget,
      );
      expect(find.text('Final message'), findsNothing);
      expect(find.text('Thinking'), findsNothing);
      expect(find.text('Ran git status'), findsNothing);
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
          metadata: const <String, dynamic>{'durationMs': 120000},
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state);

    expect(find.text('Final message'), findsNothing);
    expect(find.text('done'), findsOneWidget);
    expect(find.textContaining('Worked for'), findsNothing);
  });

  testWidgets('empty completed assistant cells are hidden', (tester) async {
    final state = SessionState(
      timelineCells: <TimelineCell>[
        _cell(
          id: 'a-empty',
          kind: TimelineCellKind.assistantMessage,
          status: TimelineCellStatus.completed,
          turnId: 't1',
          markdownText: '',
        ),
        _cell(
          id: 'a-visible',
          kind: TimelineCellKind.assistantMessage,
          status: TimelineCellStatus.completed,
          turnId: 't1',
          markdownText: 'visible assistant text',
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state);

    expect(find.text('visible assistant text'), findsOneWidget);
    expect(find.text('_no content_'), findsNothing);
  });

  testWidgets('assistant streaming renders progressive markdown', (
    tester,
  ) async {
    final state = SessionState(
      timelineCells: <TimelineCell>[
        _cell(
          id: 'a-streaming',
          kind: TimelineCellKind.assistantMessage,
          status: TimelineCellStatus.inProgress,
          turnId: 't1',
          markdownText: 'Texto **negrita** con `codigo` en stream',
          isStreaming: true,
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state);

    expect(find.byType(StreamingText), findsOneWidget);
    expect(find.textContaining('negrita'), findsOneWidget);
    expect(find.text('Streaming...'), findsOneWidget);
  });

  testWidgets('assistant completed renders markdown when content is safe', (
    tester,
  ) async {
    final state = SessionState(
      timelineCells: <TimelineCell>[
        _cell(
          id: 'a-safe-markdown',
          kind: TimelineCellKind.assistantMessage,
          status: TimelineCellStatus.completed,
          turnId: 't1',
          markdownText: 'Texto con **negrita** y `codigo`.',
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state);

    expect(find.byType(StreamingText), findsOneWidget);
    expect(find.textContaining('**negrita**'), findsNothing);
    expect(find.textContaining('negrita'), findsOneWidget);
  });

  testWidgets(
    'assistant completed renders malformed markdown without fallback',
    (tester) async {
      final state = SessionState(
        timelineCells: <TimelineCell>[
          _cell(
            id: 'a-unsafe-markdown',
            kind: TimelineCellKind.assistantMessage,
            status: TimelineCellStatus.completed,
            turnId: 't1',
            markdownText: 'Texto con `backtick abierto',
          ),
        ],
      );

      await _pumpWorkspace(tester, state: state);

      expect(find.byType(StreamingText), findsOneWidget);
      expect(find.textContaining('backtick abierto'), findsOneWidget);
    },
  );

  testWidgets(
    'timeline is wrapped in SelectionArea for cross-message selection',
    (tester) async {
      final state = SessionState(
        timelineCells: <TimelineCell>[
          _cell(
            id: 'user-selection',
            kind: TimelineCellKind.userMessage,
            status: TimelineCellStatus.completed,
            markdownText: 'primer mensaje',
          ),
          _cell(
            id: 'assistant-selection',
            kind: TimelineCellKind.assistantMessage,
            status: TimelineCellStatus.completed,
            markdownText: 'segundo mensaje',
          ),
        ],
      );

      await _pumpWorkspace(tester, state: state);

      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
    },
  );

  testWidgets('composer no longer renders markdown popup control', (
    tester,
  ) async {
    await _pumpWorkspace(tester, state: const SessionState());

    expect(find.byType(PopupMenuButton<bool>), findsNothing);
  });

  testWidgets('composer text field uses 12px horizontal content padding', (
    tester,
  ) async {
    await _pumpWorkspace(tester, state: const SessionState());

    final textField = tester.widget<TextField>(find.byType(TextField));
    final padding = textField.decoration?.contentPadding;
    expect(padding, isA<EdgeInsets>());
    final edgeInsets = padding! as EdgeInsets;
    expect(edgeInsets.left, 12);
    expect(edgeInsets.right, 12);
    expect(edgeInsets.top, 16);
    expect(edgeInsets.bottom, 8);
  });

  testWidgets('user completed renders markdown when content is safe', (
    tester,
  ) async {
    final state = SessionState(
      timelineCells: <TimelineCell>[
        _cell(
          id: 'user-safe-markdown',
          kind: TimelineCellKind.userMessage,
          status: TimelineCellStatus.completed,
          markdownText: 'Texto con **negrita** y `codigo`.',
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state);

    expect(find.byType(StreamingText), findsNothing);
    expect(find.textContaining('**negrita**'), findsNothing);
    expect(find.textContaining('negrita'), findsOneWidget);
  });

  testWidgets(
    'user completed renders malformed markdown without fallback',
    (tester) async {
      final state = SessionState(
        timelineCells: <TimelineCell>[
          _cell(
            id: 'user-unsafe-markdown',
            kind: TimelineCellKind.userMessage,
            status: TimelineCellStatus.completed,
            markdownText: 'Texto con `backtick abierto',
          ),
        ],
      );

      await _pumpWorkspace(tester, state: state);

      expect(find.byType(StreamingText), findsNothing);
      expect(find.textContaining('backtick abierto'), findsOneWidget);
    },
  );

  testWidgets('markdown mode off renders plain text for completed user', (
    tester,
  ) async {
    final state = SessionState(
      timelineCells: <TimelineCell>[
        _cell(
          id: 'user-markdown-off',
          kind: TimelineCellKind.userMessage,
          status: TimelineCellStatus.completed,
          markdownText: 'Texto con **negrita**',
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state, isMarkdownEnabled: false);

    expect(find.byType(StreamingText), findsNothing);
    expect(find.text('Texto con **negrita**'), findsOneWidget);
  });

  testWidgets('copy buttons are visible and copy message text', (tester) async {
    final previousDetector = copyMouseConnectionDetector;
    copyMouseConnectionDetector = () => false;
    addTearDown(() {
      copyMouseConnectionDetector = previousDetector;
    });

    final clipboardWrites = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardWrites.add(call);
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final state = SessionState(
      timelineCells: <TimelineCell>[
        _cell(
          id: 'user-copy',
          kind: TimelineCellKind.userMessage,
          status: TimelineCellStatus.completed,
          markdownText: 'texto user',
        ),
        _cell(
          id: 'assistant-copy',
          kind: TimelineCellKind.assistantMessage,
          status: TimelineCellStatus.completed,
          markdownText: 'texto assistant **raw**',
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state);

    expect(
      find.byKey(const ValueKey<String>('copy-user-user-copy')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('copy-assistant-assistant-copy')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('copy-user-user-copy')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(clipboardWrites.length, 1);
    expect(
      (clipboardWrites.first.arguments as Map<dynamic, dynamic>)['text'],
      'texto user',
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('copy-assistant-assistant-copy')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(clipboardWrites.length, 2);
    expect(
      (clipboardWrites.last.arguments as Map<dynamic, dynamic>)['text'],
      'texto assistant **raw**',
    );
  });

  testWidgets('user copy button is outside at lower-right of the user bubble', (
    tester,
  ) async {
    final state = SessionState(
      timelineCells: <TimelineCell>[
        _cell(
          id: 'user-pos',
          kind: TimelineCellKind.userMessage,
          status: TimelineCellStatus.completed,
          markdownText: 'mensaje corto',
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state);

    final bubbleFinder = find.byKey(
      const ValueKey<String>('user-bubble-user-pos'),
    );
    final copyFinder = find.byKey(const ValueKey<String>('copy-user-user-pos'));

    expect(bubbleFinder, findsOneWidget);
    expect(copyFinder, findsOneWidget);

    final bubbleRect = tester.getRect(bubbleFinder);
    final buttonRect = tester.getRect(copyFinder);

    expect((buttonRect.right - bubbleRect.right).abs(), lessThan(2));
    expect(buttonRect.center.dy, greaterThan(bubbleRect.bottom));
  });

  testWidgets(
    'assistant copy button is outside at lower-left of the assistant bubble',
    (tester) async {
      final state = SessionState(
        timelineCells: <TimelineCell>[
          _cell(
            id: 'assistant-pos',
            kind: TimelineCellKind.assistantMessage,
            status: TimelineCellStatus.completed,
            markdownText: 'respuesta',
          ),
        ],
      );

      await _pumpWorkspace(tester, state: state);

      final bubbleFinder = find.byKey(
        const ValueKey<String>('assistant-bubble-assistant-pos'),
      );
      final copyFinder = find.byKey(
        const ValueKey<String>('copy-assistant-assistant-pos'),
      );

      expect(bubbleFinder, findsOneWidget);
      expect(copyFinder, findsOneWidget);

      final bubbleRect = tester.getRect(bubbleFinder);
      final buttonRect = tester.getRect(copyFinder);

      expect((buttonRect.left - bubbleRect.left).abs(), lessThan(2));
      expect(buttonRect.center.dy, greaterThan(bubbleRect.bottom));
    },
  );

  testWidgets('copy buttons are hover-only with mouse connected', (
    tester,
  ) async {
    final previousDetector = copyMouseConnectionDetector;
    copyMouseConnectionDetector = () => true;
    addTearDown(() {
      copyMouseConnectionDetector = previousDetector;
    });

    final clipboardWrites = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardWrites.add(call);
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final state = SessionState(
      timelineCells: <TimelineCell>[
        _cell(
          id: 'user-hover',
          kind: TimelineCellKind.userMessage,
          status: TimelineCellStatus.completed,
          markdownText: 'texto user hover',
        ),
        _cell(
          id: 'assistant-hover',
          kind: TimelineCellKind.assistantMessage,
          status: TimelineCellStatus.completed,
          markdownText: 'texto assistant hover',
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state);

    final userCopyFinder = find.byKey(
      const ValueKey<String>('copy-user-user-hover'),
    );
    final assistantCopyFinder = find.byKey(
      const ValueKey<String>('copy-assistant-assistant-hover'),
    );
    final userZoneFinder = find.byKey(
      const ValueKey<String>('copy-zone-user-user-hover'),
    );
    final assistantZoneFinder = find.byKey(
      const ValueKey<String>('copy-zone-assistant-assistant-hover'),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: const Offset(1, 1));
    await tester.pumpAndSettle();

    await tester.tap(userCopyFinder, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(clipboardWrites, isEmpty);

    await tester.tap(assistantCopyFinder, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(clipboardWrites, isEmpty);

    await mouse.moveTo(tester.getCenter(userZoneFinder));
    await tester.pumpAndSettle();
    await tester.tap(userCopyFinder);
    await tester.pump(const Duration(milliseconds: 100));
    expect(clipboardWrites.length, 1);

    await mouse.moveTo(tester.getCenter(assistantZoneFinder));
    await tester.pumpAndSettle();
    await tester.tap(assistantCopyFinder);
    await tester.pump(const Duration(milliseconds: 100));
    expect(clipboardWrites.length, 2);
  });

  testWidgets(
    'markdown toggle buttons are hover-only with mouse connected and emit inverse value',
    (tester) async {
      final previousDetector = copyMouseConnectionDetector;
      copyMouseConnectionDetector = () => true;
      addTearDown(() {
        copyMouseConnectionDetector = previousDetector;
      });

      final toggledValues = <bool>[];
      final state = SessionState(
        timelineCells: <TimelineCell>[
          _cell(
            id: 'user-markdown-hover',
            kind: TimelineCellKind.userMessage,
            status: TimelineCellStatus.completed,
            markdownText: 'texto user hover',
          ),
          _cell(
            id: 'assistant-markdown-hover',
            kind: TimelineCellKind.assistantMessage,
            status: TimelineCellStatus.completed,
            markdownText: 'texto assistant hover',
          ),
        ],
      );

      await _pumpWorkspace(
        tester,
        state: state,
        isMarkdownEnabled: true,
        onMarkdownModeChanged: toggledValues.add,
      );

      final userToggleFinder = find.byKey(
        const ValueKey<String>('toggle-markdown-user-user-markdown-hover'),
      );
      final assistantToggleFinder = find.byKey(
        const ValueKey<String>(
          'toggle-markdown-assistant-assistant-markdown-hover',
        ),
      );
      final userZoneFinder = find.byKey(
        const ValueKey<String>('copy-zone-user-user-markdown-hover'),
      );
      final assistantZoneFinder = find.byKey(
        const ValueKey<String>('copy-zone-assistant-assistant-markdown-hover'),
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(1, 1));
      await tester.pumpAndSettle();

      await tester.tap(userToggleFinder, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(assistantToggleFinder, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(toggledValues, isEmpty);

      await mouse.moveTo(tester.getCenter(userZoneFinder));
      await tester.pumpAndSettle();
      await tester.tap(userToggleFinder);
      await tester.pump(const Duration(milliseconds: 100));
      expect(toggledValues, <bool>[false]);

      await mouse.moveTo(tester.getCenter(assistantZoneFinder));
      await tester.pumpAndSettle();
      await tester.tap(assistantToggleFinder);
      await tester.pump(const Duration(milliseconds: 100));
      expect(toggledValues, <bool>[false, false]);
    },
  );

  testWidgets('markdown toggle buttons are visible without hover on touch', (
    tester,
  ) async {
    final previousDetector = copyMouseConnectionDetector;
    copyMouseConnectionDetector = () => false;
    addTearDown(() {
      copyMouseConnectionDetector = previousDetector;
    });

    final toggledValues = <bool>[];
    final state = SessionState(
      timelineCells: <TimelineCell>[
        _cell(
          id: 'user-markdown-touch',
          kind: TimelineCellKind.userMessage,
          status: TimelineCellStatus.completed,
          markdownText: 'texto user touch',
        ),
        _cell(
          id: 'assistant-markdown-touch',
          kind: TimelineCellKind.assistantMessage,
          status: TimelineCellStatus.completed,
          markdownText: 'texto assistant touch',
        ),
      ],
    );

    await _pumpWorkspace(
      tester,
      state: state,
      isMarkdownEnabled: false,
      onMarkdownModeChanged: toggledValues.add,
    );

    final userToggleFinder = find.byKey(
      const ValueKey<String>('toggle-markdown-user-user-markdown-touch'),
    );
    final assistantToggleFinder = find.byKey(
      const ValueKey<String>(
        'toggle-markdown-assistant-assistant-markdown-touch',
      ),
    );

    expect(userToggleFinder, findsOneWidget);
    expect(assistantToggleFinder, findsOneWidget);

    await tester.tap(userToggleFinder);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(assistantToggleFinder);
    await tester.pump(const Duration(milliseconds: 100));

    expect(toggledValues, <bool>[true, true]);
  });

  testWidgets('markdown mode off renders plain text for completed assistant', (
    tester,
  ) async {
    final state = SessionState(
      timelineCells: <TimelineCell>[
        _cell(
          id: 'assistant-markdown-off',
          kind: TimelineCellKind.assistantMessage,
          status: TimelineCellStatus.completed,
          markdownText: 'Texto con **negrita**',
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state, isMarkdownEnabled: false);

    expect(find.byType(StreamingText), findsNothing);
    expect(find.text('Texto con **negrita**'), findsOneWidget);
  });

  testWidgets('single secondary row hides worked and final message', (
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

    expect(find.textContaining('Worked for'), findsNothing);
    expect(find.text('Final message'), findsNothing);
    expect(find.text('Thinking'), findsOneWidget);
  });

  testWidgets(
    'multi secondary under one minute shows worked divider with seconds and stays collapsed',
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
            title: 'Ran git status',
            detailsText: 'On branch main',
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
            metadata: const <String, dynamic>{'durationMs': 30000},
          ),
        ],
      );

      await _pumpWorkspace(tester, state: state);

      expect(find.text('Worked for 30s'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('worked-divider')),
        findsOneWidget,
      );
      expect(find.text('Thinking'), findsNothing);
      expect(find.text('Ran git status'), findsNothing);

      await tester.tap(find.text('Worked for 30s'));
      await tester.pumpAndSettle();
      expect(find.text('Thinking'), findsOneWidget);
      expect(find.text('Ran git status'), findsOneWidget);
    },
  );

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
            metadata: const <String, dynamic>{'durationMs': 120000},
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
      expect(find.text('Final message'), findsNothing);

      await tester.tap(find.text('Thinking'));
      await tester.pumpAndSettle();
      expect(find.text('Reasoning detail text'), findsOneWidget);

      await tester.tap(find.text('git diff'));
      await tester.pumpAndSettle();
      expect(find.text('Reasoning detail text'), findsOneWidget);
      expect(find.text('diff --git a b'), findsOneWidget);
    },
  );

  testWidgets('progressText renders as plain inline row inside worked', (
    tester,
  ) async {
    final state = SessionState(
      timelineCells: <TimelineCell>[
        _cell(
          id: 'u1',
          kind: TimelineCellKind.userMessage,
          status: TimelineCellStatus.completed,
          turnId: 't-progress',
          markdownText: 'hello',
        ),
        _cell(
          id: 'progress1',
          kind: TimelineCellKind.progressText,
          status: TimelineCellStatus.completed,
          turnId: 't-progress',
          markdownText: 'Interim assistant text',
          metadata: const <String, dynamic>{
            'progressPhaseIndex': 0,
            'isInterim': true,
          },
        ),
        _cell(
          id: 'tool1',
          kind: TimelineCellKind.toolCall,
          status: TimelineCellStatus.completed,
          turnId: 't-progress',
          title: 'Ran git status',
          detailsText: 'On branch main',
          isCollapsed: true,
        ),
        _cell(
          id: 'a1',
          kind: TimelineCellKind.assistantMessage,
          status: TimelineCellStatus.completed,
          turnId: 't-progress',
          markdownText: 'final answer',
        ),
        _cell(
          id: 'sep1',
          kind: TimelineCellKind.turnSeparator,
          status: TimelineCellStatus.completed,
          turnId: 't-progress',
          metadata: const <String, dynamic>{'durationMs': 120000},
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state);

    expect(find.textContaining('Worked for'), findsOneWidget);
    expect(find.text('Interim assistant text'), findsNothing);

    await tester.tap(find.textContaining('Worked for'));
    await tester.pumpAndSettle();

    expect(find.text('Interim assistant text'), findsOneWidget);
    expect(find.text('Final message'), findsNothing);

    final interimDx = tester.getTopLeft(find.text('Interim assistant text')).dx;
    final toolDx = tester.getTopLeft(find.text('Ran git status')).dx;
    expect((interimDx - toolDx).abs(), lessThan(28));
  });

  testWidgets('single progressText secondary hides worked and final message', (
    tester,
  ) async {
    final state = SessionState(
      timelineCells: <TimelineCell>[
        _cell(
          id: 'u1',
          kind: TimelineCellKind.userMessage,
          status: TimelineCellStatus.completed,
          turnId: 't-progress-single',
          markdownText: 'hello',
        ),
        _cell(
          id: 'progress1',
          kind: TimelineCellKind.progressText,
          status: TimelineCellStatus.completed,
          turnId: 't-progress-single',
          markdownText: 'Interim only',
          metadata: const <String, dynamic>{
            'progressPhaseIndex': 0,
            'isInterim': true,
          },
        ),
        _cell(
          id: 'a1',
          kind: TimelineCellKind.assistantMessage,
          status: TimelineCellStatus.completed,
          turnId: 't-progress-single',
          markdownText: 'final answer',
        ),
        _cell(
          id: 'sep1',
          kind: TimelineCellKind.turnSeparator,
          status: TimelineCellStatus.completed,
          turnId: 't-progress-single',
          metadata: const <String, dynamic>{'durationMs': 1200},
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state);

    expect(find.textContaining('Worked for'), findsNothing);
    expect(find.text('Final message'), findsNothing);
    expect(find.text('Interim only'), findsOneWidget);
  });

  testWidgets('progressText rows render markdown content', (tester) async {
    final state = SessionState(
      timelineCells: <TimelineCell>[
        _cell(
          id: 'u1',
          kind: TimelineCellKind.userMessage,
          status: TimelineCellStatus.completed,
          turnId: 't-progress-markdown',
          markdownText: 'hello',
        ),
        _cell(
          id: 'progress-md',
          kind: TimelineCellKind.progressText,
          status: TimelineCellStatus.completed,
          turnId: 't-progress-markdown',
          markdownText: 'Texto con **negrita** y `codigo`.',
          metadata: const <String, dynamic>{
            'progressPhaseIndex': 0,
            'isInterim': true,
          },
        ),
        _cell(
          id: 'a1',
          kind: TimelineCellKind.assistantMessage,
          status: TimelineCellStatus.completed,
          turnId: 't-progress-markdown',
          markdownText: 'final answer',
        ),
        _cell(
          id: 'sep1',
          kind: TimelineCellKind.turnSeparator,
          status: TimelineCellStatus.completed,
          turnId: 't-progress-markdown',
          metadata: const <String, dynamic>{'durationMs': 1200},
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state);

    expect(find.textContaining('**negrita**'), findsNothing);
    expect(find.textContaining('negrita'), findsOneWidget);
    expect(find.textContaining('codigo'), findsOneWidget);
  });

  testWidgets('empty progressText does not force worked section visibility', (
    tester,
  ) async {
    final state = SessionState(
      timelineCells: <TimelineCell>[
        _cell(
          id: 'u1',
          kind: TimelineCellKind.userMessage,
          status: TimelineCellStatus.completed,
          turnId: 't-empty-progress',
          markdownText: 'hello',
        ),
        _cell(
          id: 'progress-empty',
          kind: TimelineCellKind.progressText,
          status: TimelineCellStatus.completed,
          turnId: 't-empty-progress',
          markdownText: '   ',
          metadata: const <String, dynamic>{
            'progressPhaseIndex': 0,
            'isInterim': true,
          },
        ),
        _cell(
          id: 'tool1',
          kind: TimelineCellKind.toolCall,
          status: TimelineCellStatus.completed,
          turnId: 't-empty-progress',
          title: 'Ran git status',
          detailsText: 'On branch main',
          isCollapsed: true,
        ),
        _cell(
          id: 'a1',
          kind: TimelineCellKind.assistantMessage,
          status: TimelineCellStatus.completed,
          turnId: 't-empty-progress',
          markdownText: 'final answer',
        ),
        _cell(
          id: 'sep1',
          kind: TimelineCellKind.turnSeparator,
          status: TimelineCellStatus.completed,
          turnId: 't-empty-progress',
          metadata: const <String, dynamic>{'durationMs': 1200},
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state);

    expect(find.textContaining('Worked for'), findsNothing);
    expect(find.text('Final message'), findsNothing);
    expect(find.text('Ran git status'), findsOneWidget);
  });

  testWidgets(
    'stream-committed item keeps streamed text and ignores final payload text',
    (tester) async {
      var state = const SessionState();
      state = reduceNotification(
        state,
        _event('turn/started', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-widget-dedupe',
            'threadId': 't',
          },
        }),
      );
      state = reduceNotification(
        state,
        _event('item/started', <String, dynamic>{
          'turnId': 'turn-widget-dedupe',
          'item': <String, dynamic>{
            'id': 'cmd-widget-dedupe',
            'type': 'commandExecution',
            'command': 'ls',
            'status': 'inProgress',
          },
        }),
      );
      state = reduceNotification(
        state,
        _event('item/agentMessage/delta', <String, dynamic>{
          'turnId': 'turn-widget-dedupe',
          'itemId': 'msg-widget-dedupe',
          'delta': 'trabajando y validando\n',
        }),
      );
      state = reduceNotification(
        state,
        _event('item/completed', <String, dynamic>{
          'turnId': 'turn-widget-dedupe',
          'item': <String, dynamic>{
            'id': 'msg-widget-dedupe',
            'type': 'agentMessage',
            'status': 'completed',
            'text': 'y validando cambios finales',
          },
        }),
      );
      state = reduceNotification(
        state,
        _event('turn/completed', <String, dynamic>{
          'turn': <String, dynamic>{
            'id': 'turn-widget-dedupe',
            'threadId': 't',
            'status': 'completed',
            'durationMs': 120000,
          },
        }),
      );

      await _pumpWorkspace(tester, state: state);
      final workedFinder = find.textContaining('Worked for');
      if (workedFinder.evaluate().isNotEmpty) {
        await tester.tap(workedFinder);
        await tester.pumpAndSettle();
      }

      expect(find.textContaining('trabajando y validando'), findsOneWidget);
      expect(find.textContaining('y validando cambios finales'), findsNothing);
    },
  );

  testWidgets('exploratory tool calls are grouped as explored row', (
    tester,
  ) async {
    final state = SessionState(
      timelineCells: <TimelineCell>[
        _cell(
          id: 'u1',
          kind: TimelineCellKind.userMessage,
          status: TimelineCellStatus.completed,
          turnId: 'turn-explore',
          markdownText: 'inspect files',
        ),
        _cell(
          id: 'tool-read',
          kind: TimelineCellKind.toolCall,
          status: TimelineCellStatus.completed,
          turnId: 'turn-explore',
          title: 'Read',
          subtitle: 'cat README.md',
          detailsText: 'README contents',
          metadata: const <String, dynamic>{
            'isExploratory': true,
            'exploreBucket': 'file',
          },
          isCollapsed: true,
        ),
        _cell(
          id: 'tool-search',
          kind: TimelineCellKind.toolCall,
          status: TimelineCellStatus.completed,
          turnId: 'turn-explore',
          title: 'Search',
          subtitle: 'rg TODO',
          detailsText: 'TODO line',
          metadata: const <String, dynamic>{
            'isExploratory': true,
            'exploreBucket': 'search',
          },
          isCollapsed: true,
        ),
        _cell(
          id: 'assistant',
          kind: TimelineCellKind.assistantMessage,
          status: TimelineCellStatus.completed,
          turnId: 'turn-explore',
          markdownText: 'done',
        ),
        _cell(
          id: 'sep',
          kind: TimelineCellKind.turnSeparator,
          status: TimelineCellStatus.completed,
          turnId: 'turn-explore',
          metadata: const <String, dynamic>{'durationMs': 10000},
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state);

    expect(find.textContaining('Worked for'), findsNothing);
    expect(find.text('Final message'), findsNothing);
    expect(find.text('Explored 1 file, 1 search'), findsOneWidget);

    await tester.tap(find.text('Explored 1 file, 1 search'));
    await tester.pumpAndSettle();
    expect(find.text('Read · cat README.md'), findsOneWidget);
    expect(find.text('Search · rg TODO'), findsOneWidget);
  });

  testWidgets('streaming exploratory calls start collapsed and expand on tap', (
    tester,
  ) async {
    final state = SessionState(
      timelineCells: <TimelineCell>[
        _cell(
          id: 'tool-read-live',
          kind: TimelineCellKind.toolCall,
          status: TimelineCellStatus.inProgress,
          turnId: 'turn-live',
          title: 'Read',
          subtitle: 'cat README.md',
          detailsText: 'line 1',
          metadata: const <String, dynamic>{
            'isExploratory': true,
            'exploreBucket': 'file',
          },
          isCollapsed: false,
        ),
        _cell(
          id: 'tool-search-live',
          kind: TimelineCellKind.toolCall,
          status: TimelineCellStatus.inProgress,
          turnId: 'turn-live',
          title: 'Search',
          subtitle: 'rg TODO',
          detailsText: 'match',
          metadata: const <String, dynamic>{
            'isExploratory': true,
            'exploreBucket': 'search',
          },
          isCollapsed: false,
        ),
      ],
    );

    await _pumpWorkspace(tester, state: state);

    expect(find.text('Exploring'), findsOneWidget);
    expect(find.text('Read · cat README.md'), findsNothing);
    expect(find.text('Search · rg TODO'), findsNothing);

    await tester.tap(find.text('Exploring'));
    await tester.pumpAndSettle();

    expect(find.text('Read · cat README.md'), findsOneWidget);
    expect(find.text('Search · rg TODO'), findsOneWidget);
  });

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
          id: 'tool-ms',
          kind: TimelineCellKind.toolCall,
          status: TimelineCellStatus.completed,
          turnId: 'turn-ms',
          title: 'Ran pwd',
          detailsText: '/repo',
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
          id: 'tool-day',
          kind: TimelineCellKind.toolCall,
          status: TimelineCellStatus.completed,
          turnId: 'turn-day',
          title: 'Ran pwd',
          detailsText: '/repo',
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

  testWidgets(
    'timeline scrollable spans viewport width and content stays centered',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpWorkspace(
        tester,
        state: stateWithActiveSession(timeline: _longAssistantTimeline()),
      );

      final listRect = tester.getRect(
        find.byKey(const ValueKey<String>('timeline-list')),
      );
      final scaffoldRect = tester.getRect(find.byType(Scaffold));
      final contentRect = tester.getRect(
        find.byKey(const ValueKey<String>('timeline-content-container')),
      );

      expect((listRect.width - scaffoldRect.width).abs(), lessThan(1.0));
      expect(contentRect.width, lessThanOrEqualTo(720));
      final leftGap = contentRect.left - listRect.left;
      final rightGap = listRect.right - contentRect.right;
      expect((leftGap - rightGap).abs(), lessThan(2.0));
    },
  );

  testWidgets('scroll-to-bottom button stays horizontally centered', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpWorkspace(
      tester,
      state: stateWithActiveSession(timeline: _longAssistantTimeline()),
    );
    await tester.pumpAndSettle();

    expect(_scrollToBottomButton(tester).onPressed, isNotNull);

    final buttonRect = tester.getRect(
      find.byKey(const ValueKey<String>('scroll-to-bottom-button')),
    );
    final listRect = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-list')),
    );
    expect((buttonRect.center.dx - listRect.center.dx).abs(), lessThan(2.0));
  });

  testWidgets('shows scroll-to-bottom button when user scrolls up', (
    tester,
  ) async {
    await _pumpWorkspace(
      tester,
      state: stateWithActiveSession(timeline: _longAssistantTimeline()),
    );

    final listFinder = find.byKey(const ValueKey<String>('timeline-list'));
    await tester.fling(listFinder, const Offset(0, -3000), 6000);
    await tester.pumpAndSettle();

    expect(_scrollToBottomButton(tester).onPressed, isNull);

    await tester.drag(listFinder, const Offset(0, 300));
    await tester.pumpAndSettle();

    expect(_scrollToBottomButton(tester).onPressed, isNotNull);
  });

  testWidgets('hides scroll-to-bottom button when at bottom', (tester) async {
    await _pumpWorkspace(
      tester,
      state: stateWithActiveSession(timeline: _longAssistantTimeline()),
    );

    final listFinder = find.byKey(const ValueKey<String>('timeline-list'));
    await tester.fling(listFinder, const Offset(0, -3000), 6000);
    await tester.pumpAndSettle();

    expect(_scrollToBottomButton(tester).onPressed, isNull);
  });

  testWidgets('tapping scroll-to-bottom button goes to latest message', (
    tester,
  ) async {
    await _pumpWorkspace(
      tester,
      state: stateWithActiveSession(timeline: _longAssistantTimeline()),
    );

    expect(_scrollToBottomButton(tester).onPressed, isNotNull);

    await tester.tap(
      find.byKey(const ValueKey<String>('scroll-to-bottom-button')),
    );
    await tester.pumpAndSettle();

    expect(_scrollToBottomButton(tester).onPressed, isNull);
  });

  testWidgets('auto-scrolls on AI updates when user is at bottom', (
    tester,
  ) async {
    final initialTimeline = _longAssistantTimeline(count: 50);
    await _pumpWorkspace(
      tester,
      state: stateWithActiveSession(timeline: initialTimeline),
    );

    final listFinder = find.byKey(const ValueKey<String>('timeline-list'));
    await tester.fling(listFinder, const Offset(0, -3000), 6000);
    await tester.pumpAndSettle();
    expect(_scrollToBottomButton(tester).onPressed, isNull);

    final updatedTimeline = <TimelineCell>[
      ...initialTimeline,
      _cell(
        id: 'assistant-latest',
        kind: TimelineCellKind.assistantMessage,
        status: TimelineCellStatus.completed,
        markdownText: 'assistant latest',
      ),
    ];
    await _pumpWorkspace(
      tester,
      state: stateWithActiveSession(timeline: updatedTimeline),
    );

    expect(_scrollToBottomButton(tester).onPressed, isNull);
  });

  testWidgets('does not auto-scroll on AI updates when user is above bottom', (
    tester,
  ) async {
    final initialTimeline = _longAssistantTimeline(count: 50);
    await _pumpWorkspace(
      tester,
      state: stateWithActiveSession(timeline: initialTimeline),
    );

    final listFinder = find.byKey(const ValueKey<String>('timeline-list'));
    await tester.fling(listFinder, const Offset(0, -3000), 6000);
    await tester.pumpAndSettle();
    await tester.drag(listFinder, const Offset(0, 280));
    await tester.pumpAndSettle();

    expect(_scrollToBottomButton(tester).onPressed, isNotNull);

    final updatedTimeline = <TimelineCell>[
      ...initialTimeline,
      _cell(
        id: 'assistant-latest',
        kind: TimelineCellKind.assistantMessage,
        status: TimelineCellStatus.completed,
        markdownText: 'assistant latest',
      ),
    ];
    await _pumpWorkspace(
      tester,
      state: stateWithActiveSession(timeline: updatedTimeline),
    );

    expect(_scrollToBottomButton(tester).onPressed, isNotNull);
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

  testWidgets('sending input triggers auto-scroll to bottom', (tester) async {
    var sentCount = 0;
    await _pumpWorkspace(
      tester,
      state: stateWithActiveSession(
        timeline: _longAssistantTimeline(count: 60),
      ),
      onSendInput: (_) => sentCount += 1,
    );

    expect(_scrollToBottomButton(tester).onPressed, isNotNull);

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'new user prompt');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(sentCount, 1);
    expect(_scrollToBottomButton(tester).onPressed, isNull);
  });

  testWidgets('composer works in pre-session mode when workspace is selected', (
    tester,
  ) async {
    var sentCount = 0;
    String? lastMessage;

    await _pumpWorkspace(
      tester,
      state: const SessionState(
        selectedWorkspacePath: '/repo',
        preSessionModelId: 'gpt-5.3-codex',
      ),
      onSendInput: (value) {
        sentCount += 1;
        lastMessage = value;
      },
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'first prompt');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(sentCount, 1);
    expect(lastMessage, 'first prompt');
  });

  testWidgets(
    'reasoning selector shows only supported options for mini and emits selection',
    (tester) async {
      String? selectedEffort;
      await _pumpWorkspace(
        tester,
        state: const SessionState(
          selectedWorkspacePath: '/repo',
          preSessionModelId: 'gpt-5.1-codex-mini',
          preSessionReasoningEffort: 'high',
        ),
        supportedReasoningEfforts: const <String>['medium', 'high'],
        activeReasoningEffort: 'high',
        onReasoningEffortChanged: (value) => selectedEffort = value,
      );

      await tester.tap(find.text('High').first);
      await tester.pumpAndSettle();

      expect(find.text('Medium'), findsOneWidget);
      expect(find.text('Low'), findsNothing);
      expect(find.text('Extra High'), findsNothing);

      await tester.tap(find.text('Medium').last);
      await tester.pumpAndSettle();

      expect(selectedEffort, 'medium');
    },
  );

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

  testWidgets('shows stop button while a turn is running', (tester) async {
    await _pumpWorkspace(
      tester,
      state: stateWithActiveSession(),
      isTurnRunning: true,
    );

    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsNothing);
  });

  testWidgets('tapping stop triggers interrupt callback', (tester) async {
    var interruptCount = 0;
    await _pumpWorkspace(
      tester,
      state: stateWithActiveSession(),
      isTurnRunning: true,
      onInterruptTurn: () => interruptCount += 1,
    );

    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();

    expect(interruptCount, 1);
  });

  testWidgets('while running, Enter does not send a message', (tester) async {
    var sentCount = 0;
    await _pumpWorkspace(
      tester,
      state: stateWithActiveSession(),
      isTurnRunning: true,
      onSendInput: (_) => sentCount += 1,
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'should not send');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(sentCount, 0);
    expect(find.byIcon(Icons.stop), findsOneWidget);
  });

  testWidgets('interrupting state disables stop and shows spinner', (
    tester,
  ) async {
    var interruptCount = 0;
    await _pumpWorkspace(
      tester,
      state: stateWithActiveSession(),
      isTurnRunning: true,
      isInterrupting: true,
      onInterruptTurn: () => interruptCount += 1,
    );

    expect(find.byIcon(Icons.stop), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    final sendOrStopButton = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('composer-send-stop-button')),
    );
    expect(sendOrStopButton.onPressed, isNull);
    expect(interruptCount, 0);
  });

  testWidgets(
    'user stop notice renders outside worked and remains visible when worked is collapsed',
    (tester) async {
      final state = SessionState(
        timelineCells: <TimelineCell>[
          _cell(
            id: 'u1',
            kind: TimelineCellKind.userMessage,
            status: TimelineCellStatus.completed,
            turnId: 't-stop',
            markdownText: 'check readme',
          ),
          _cell(
            id: 'reason-stop',
            kind: TimelineCellKind.reasoning,
            status: TimelineCellStatus.completed,
            turnId: 't-stop',
            title: 'Thinking',
            markdownText: 'detail',
            isCollapsed: true,
          ),
          _cell(
            id: 'tool-stop',
            kind: TimelineCellKind.toolCall,
            status: TimelineCellStatus.completed,
            turnId: 't-stop',
            title: 'Read',
            subtitle: 'readme.md',
            detailsText: '...',
            isCollapsed: true,
          ),
          _cell(
            id: 'a-stop',
            kind: TimelineCellKind.assistantMessage,
            status: TimelineCellStatus.completed,
            turnId: 't-stop',
            markdownText: 'partial response',
          ),
          _cell(
            id: 'n-stop',
            kind: TimelineCellKind.systemNotice,
            status: TimelineCellStatus.info,
            turnId: 't-stop',
            markdownText: 'Stopped by user',
            metadata: const <String, dynamic>{
              'noticeType': 'user_stop',
              'uiPlacement': 'outside_worked',
              'ephemeralInputOnly': true,
            },
          ),
          _cell(
            id: 'sep-stop',
            kind: TimelineCellKind.turnSeparator,
            status: TimelineCellStatus.declined,
            turnId: 't-stop',
            metadata: const <String, dynamic>{'durationMs': 120000},
          ),
        ],
      );

      await _pumpWorkspace(tester, state: state);

      expect(find.text('Worked for 2m 0s'), findsOneWidget);
      expect(find.text('Thinking'), findsNothing);
      expect(find.text('Read · readme.md'), findsNothing);
      expect(find.text('Stopped by user'), findsOneWidget);
    },
  );

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
