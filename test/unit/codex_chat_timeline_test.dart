import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:alera/src/features/codex_chat/domain/codex_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

part 'codex_chat_timeline_legacy_test_cases.dart';

Map<String, Object?> _message(String method, Map<String, Object?> params) =>
    <String, Object?>{'method': method, 'params': params};

void main() {
  final now = DateTime.utc(2026, 8, 2, 12);

  test('coalesces progressive assistant deltas by item id', () {
    var cells = <CodexTimelineCell>[];
    cells = CodexTimelineReducer.reduce(
      cells,
      _message('turn/started', <String, Object?>{
        'turn': <String, Object?>{'id': 'turn-1'},
      }),
      now: now,
    );
    cells = CodexTimelineReducer.reduce(
      cells,
      _message('item/agentMessage/delta', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'answer-1',
        'delta': 'Hello',
      }),
      now: now,
    );
    cells = CodexTimelineReducer.reduce(
      cells,
      _message('item/agentMessage/delta', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'answer-1',
        'delta': ' world',
      }),
      now: now,
    );
    expect(cells, hasLength(2));
    final answer = cells.singleWhere((cell) => cell.itemId == 'answer-1');
    expect(answer.kind, CodexTimelineKind.assistantMessage);
    expect(answer.markdownText, 'Hello world');
    expect(answer.isStreaming, isTrue);
  });

  test(
    'keeps commentary, reasoning, command output, diff, plan and subagent rows distinct',
    () {
      var cells = <CodexTimelineCell>[];
      cells = CodexTimelineReducer.reduce(
        cells,
        _message('item/agentMessage/delta', <String, Object?>{
          'turnId': 'turn-1',
          'itemId': 'commentary-1',
          'phase': 'commentary',
          'delta': 'Inspecting files',
        }),
        now: now,
      );
      cells = CodexTimelineReducer.reduce(
        cells,
        _message('item/reasoning/textDelta', <String, Object?>{
          'turnId': 'turn-1',
          'itemId': 'reason-1',
          'delta': 'Checking the plan',
        }),
        now: now,
      );
      cells = CodexTimelineReducer.reduce(
        cells,
        _message('item/started', <String, Object?>{
          'turnId': 'turn-1',
          'item': <String, Object?>{
            'id': 'command-1',
            'type': 'commandExecution',
            'command': 'git status',
          },
        }),
        now: now,
      );
      cells = CodexTimelineReducer.reduce(
        cells,
        _message('item/commandExecution/outputDelta', <String, Object?>{
          'turnId': 'turn-1',
          'itemId': 'command-1',
          'delta': 'clean',
        }),
        now: now,
      );
      cells = CodexTimelineReducer.reduce(
        cells,
        _message('turn/diff/updated', <String, Object?>{
          'turnId': 'turn-1',
          'diff': 'diff --git a/file b/file',
        }),
        now: now,
      );
      cells = CodexTimelineReducer.reduce(
        cells,
        _message('item/started', <String, Object?>{
          'turnId': 'turn-1',
          'item': <String, Object?>{'id': 'plan-1', 'type': 'plan'},
        }),
        now: now,
      );
      cells = CodexTimelineReducer.reduce(
        cells,
        _message('item/started', <String, Object?>{
          'turnId': 'turn-1',
          'item': <String, Object?>{'id': 'agent-1', 'type': 'subAgent'},
        }),
        now: now,
      );
      expect(
        cells.map((cell) => cell.kind),
        containsAll(<CodexTimelineKind>[
          CodexTimelineKind.progressText,
          CodexTimelineKind.reasoning,
          CodexTimelineKind.command,
          CodexTimelineKind.diff,
          CodexTimelineKind.plan,
          CodexTimelineKind.subAgent,
        ]),
      );
      expect(
        cells.singleWhere((cell) => cell.itemId == 'command-1').detailsText,
        'clean',
      );
    },
  );

  test('replaces full diff snapshots instead of appending them', () {
    final first = CodexTimelineReducer.reduce(
      const <CodexTimelineCell>[],
      _message('turn/diff/updated', <String, Object?>{
        'turnId': 'turn-1',
        'diff': 'first snapshot',
      }),
      now: now,
    );
    final second = CodexTimelineReducer.reduce(
      first,
      _message('turn/diff/updated', <String, Object?>{
        'turnId': 'turn-1',
        'diff': 'second snapshot',
      }),
      now: now,
    );
    expect(
      second.singleWhere((cell) => cell.id == 'diff-turn-1').detailsText,
      'second snapshot',
    );
  });

  test('turn completion closes every streaming cell and marks failures', () {
    var cells = CodexTimelineReducer.reduce(
      <CodexTimelineCell>[],
      _message('item/agentMessage/delta', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'answer-1',
        'delta': 'partial',
      }),
      now: now,
    );
    cells = CodexTimelineReducer.reduce(
      cells,
      _message('turn/failed', <String, Object?>{
        'turn': <String, Object?>{'id': 'turn-1'},
      }),
      now: now,
    );
    expect(cells.single.status, CodexTimelineStatus.failed);
    expect(cells.single.isStreaming, isFalse);
  });

  test('turn completion records server duration on the separator', () {
    var cells = CodexTimelineReducer.reduce(
      <CodexTimelineCell>[],
      _message('turn/started', <String, Object?>{
        'turn': <String, Object?>{
          'id': 'turn-1',
          'startedAt': '2026-08-03T12:00:00Z',
        },
      }),
      now: now,
    );
    cells = CodexTimelineReducer.reduce(
      cells,
      _message('turn/completed', <String, Object?>{
        'turn': <String, Object?>{
          'id': 'turn-1',
          'completedAt': '2026-08-03T12:00:01.250Z',
          'durationMs': 1250,
        },
      }),
      now: now.add(const Duration(milliseconds: 1250)),
    );
    final separator = cells.singleWhere(
      (cell) => cell.kind == CodexTimelineKind.turnSeparator,
    );
    expect(separator.metadata['computedDurationMs'], 1250);
    expect(separator.metadata['completedAt'], '2026-08-03T12:00:01.250Z');
  });

  test('maps modern app-server item variants and rich metadata', () {
    var cells = <CodexTimelineCell>[];
    for (final item in <Map<String, Object?>>[
      <String, Object?>{
        'id': 'search',
        'type': 'webSearch',
        'query': 'Alera',
        'action': <String, Object?>{'type': 'search', 'query': 'Alera'},
      },
      <String, Object?>{
        'id': 'dynamic',
        'type': 'dynamicToolCall',
        'tool': 'inspect',
        'arguments': <String, Object?>{'path': 'README.md'},
        'contentItems': <Object?>[
          <String, Object?>{'type': 'inputText', 'text': 'done'},
        ],
        'durationMs': 42,
      },
      <String, Object?>{'id': 'view', 'type': 'imageView', 'path': 'a.png'},
      <String, Object?>{'id': 'compact', 'type': 'contextCompaction'},
    ]) {
      cells = CodexTimelineReducer.reduce(
        cells,
        _message('item/completed', <String, Object?>{
          'turnId': 'turn-1',
          'item': item,
        }),
        now: now,
      );
    }
    expect(cells, hasLength(4));
    expect(
      cells.every((cell) => cell.kind == CodexTimelineKind.toolCall),
      isTrue,
    );
    expect(cells[0].title, 'Web search');
    expect(cells[0].metadata['query'], 'Alera');
    expect(cells[1].title, 'inspect');
    expect(cells[1].metadata['durationMs'], 42);
    expect(cells[1].detailsText, contains('done'));
    expect(cells[2].title, 'Viewed image');
    expect(cells[3].title, 'Compacted context');
  });

  test('maps standalone command and file streams to specific kinds', () {
    var cells = CodexTimelineReducer.reduce(
      <CodexTimelineCell>[],
      _message('item/commandExecution/outputDelta', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'command-1',
        'delta': 'done',
      }),
      now: now,
    );
    cells = CodexTimelineReducer.reduce(
      cells,
      _message('item/fileChange/outputDelta', <String, Object?>{
        'turnId': 'turn-1',
        'itemId': 'files-1',
        'delta': 'diff',
      }),
      now: now,
    );
    expect(
      cells.singleWhere((cell) => cell.itemId == 'command-1').kind,
      CodexTimelineKind.command,
    );
    expect(
      cells.singleWhere((cell) => cell.itemId == 'files-1').kind,
      CodexTimelineKind.diff,
    );
  });

  registerCodexTimelineLegacyTests(now);
}
