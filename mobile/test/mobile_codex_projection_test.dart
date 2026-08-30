import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile keeps Working visible while assistant text streams', () {
    const activeTurnId = 'turn-working';
    final rows = MobileCodexTimelineProjection.project(
      <MobileCodexTimelineCell>[
        MobileCodexTimelineCell(
          id: 'separator',
          kind: 'turnSeparator',
          status: 'info',
          turnId: activeTurnId,
          createdAt: DateTime.utc(2026, 8, 9),
        ),
        const MobileCodexTimelineCell(
          id: 'user',
          kind: 'userMessage',
          status: 'completed',
          turnId: activeTurnId,
          markdownText: 'Start',
        ),
        const MobileCodexTimelineCell(
          id: 'assistant',
          kind: 'assistantMessage',
          status: 'inProgress',
          turnId: activeTurnId,
          markdownText: 'Streaming answer',
          isStreaming: true,
        ),
      ],
      activeTurnId: activeTurnId,
    );

    expect(rows.map((row) => row.kind), <MobileCodexPresentationKind>[
      MobileCodexPresentationKind.cell,
      MobileCodexPresentationKind.working,
      MobileCodexPresentationKind.cell,
    ]);
    expect(rows.first.cell?.id, 'user');
    expect(rows[1].startedAt, DateTime.utc(2026, 8, 9));
  });

  test('mobile keeps steering messages after Working headers', () {
    const activeTurnId = 'turn-steering';
    final rows = MobileCodexTimelineProjection.project(
      const <MobileCodexTimelineCell>[
        MobileCodexTimelineCell(
          id: 'separator',
          kind: 'turnSeparator',
          status: 'info',
          turnId: activeTurnId,
        ),
        MobileCodexTimelineCell(
          id: 'prompt',
          kind: 'userMessage',
          status: 'completed',
          turnId: activeTurnId,
          markdownText: 'Start',
        ),
        MobileCodexTimelineCell(
          id: 'steering',
          kind: 'userMessage',
          status: 'completed',
          turnId: activeTurnId,
          markdownText: 'Change direction',
          metadata: <String, Object?>{'isSteering': true},
        ),
      ],
      activeTurnId: activeTurnId,
    );

    expect(rows.first.cell?.id, 'prompt');
    expect(rows[1].kind, MobileCodexPresentationKind.working);
    expect(rows.last.cell?.id, 'steering');
  });

  test('mobile classifies every internal turn-work row as collapsible', () {
    const turnId = 'turn-secondary';
    final rows = MobileCodexTimelineProjection.project(
      const <MobileCodexTimelineCell>[
        MobileCodexTimelineCell(
          id: 'separator',
          kind: 'turnSeparator',
          status: 'completed',
          turnId: turnId,
        ),
        MobileCodexTimelineCell(
          id: 'sub-agent',
          kind: 'subAgent',
          status: 'completed',
          turnId: turnId,
          markdownText: 'Delegated work',
        ),
        MobileCodexTimelineCell(
          id: 'question',
          kind: 'questionAnswer',
          status: 'completed',
          turnId: turnId,
          markdownText: 'Answered question',
        ),
        MobileCodexTimelineCell(
          id: 'progress',
          kind: 'progressText',
          status: 'completed',
          turnId: turnId,
          markdownText: 'Internal progress',
        ),
        MobileCodexTimelineCell(
          id: 'outside',
          kind: 'progressText',
          status: 'completed',
          turnId: turnId,
          markdownText: 'Outside result',
          metadata: <String, Object?>{'uiPlacement': 'outside_worked'},
        ),
      ],
      activeTurnId: null,
    );

    expect(rows.first.turnActivityCount, 3);
    expect(
      rows
          .where((row) => row.cell?.id != 'outside')
          .skip(1)
          .every((row) => row.isTurnActivity),
      isTrue,
    );
    expect(
      rows.singleWhere((row) => row.cell?.id == 'outside').isTurnActivity,
      isFalse,
    );
  });

  test('mobile places restored turn prompts before Worked headers', () {
    const turnId = 'turn-restored';
    final rows = MobileCodexTimelineProjection.project(
      const <MobileCodexTimelineCell>[
        MobileCodexTimelineCell(
          id: 'separator',
          kind: 'turnSeparator',
          status: 'completed',
          turnId: turnId,
        ),
        MobileCodexTimelineCell(
          id: 'user',
          kind: 'userMessage',
          status: 'completed',
          turnId: turnId,
          markdownText: 'Inspect the repository',
        ),
        MobileCodexTimelineCell(
          id: 'command',
          kind: 'command',
          status: 'completed',
          turnId: turnId,
          title: 'Read files',
        ),
      ],
      activeTurnId: null,
    );

    expect(rows.map((row) => row.cell?.id), <String?>[
      'user',
      'separator',
      'command',
    ]);
  });

  test('mobile omits only successful empty file change placeholders', () {
    final rows = MobileCodexTimelineProjection.project(
      const <MobileCodexTimelineCell>[
        MobileCodexTimelineCell(
          id: 'empty',
          kind: 'diff',
          status: 'completed',
          detailsText: '[]',
          metadata: <String, Object?>{'changes': <Object?>[]},
        ),
        MobileCodexTimelineCell(
          id: 'failed',
          kind: 'diff',
          status: 'failed',
          metadata: <String, Object?>{'changes': <Object?>[]},
        ),
        MobileCodexTimelineCell(
          id: 'changed',
          kind: 'diff',
          status: 'completed',
          detailsText: '[]',
          metadata: <String, Object?>{
            'changes': <Object?>[
              <String, Object?>{'path': 'README.md'},
            ],
          },
        ),
      ],
      activeTurnId: null,
    );

    expect(rows, hasLength(1));
    expect(rows.single.activityCells.map((cell) => cell.id), <String>[
      'failed',
      'changed',
    ]);
  });
}
