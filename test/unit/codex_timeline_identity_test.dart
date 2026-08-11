import 'package:alera/src/features/codex_chat/domain/codex_timeline.dart';
import 'package:alera/src/features/codex_chat/domain/codex_timeline_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy phase matches one explicit remapped agent cell', () {
    final candidates = <CodexTimelineCell>[
      _cell('legacy-1'),
      _cell('legacy-2'),
    ];
    final replacements = <CodexTimelineCell>[
      _cell('modern-commentary', phase: 'commentary'),
      _cell('modern-final', phase: 'final_answer'),
    ];

    expect(
      codexTimelineCellsWithoutClaimedMatches(candidates, replacements),
      isEmpty,
    );
    expect(
      codexTimelineCellsWithoutClaimedMatches(
        candidates,
        replacements.take(1).toList(),
      ),
      hasLength(1),
    );
  });

  test('two explicit stream phases remain distinct', () {
    final candidates = <CodexTimelineCell>[
      _cell('commentary', phase: 'commentary'),
    ];
    final replacements = <CodexTimelineCell>[
      _cell('final', phase: 'final_answer'),
    ];

    expect(
      codexTimelineCellsWithoutClaimedMatches(candidates, replacements),
      candidates,
    );
  });

  test('phase-less history claims one explicit stream phase', () {
    final candidates = <CodexTimelineCell>[
      _cell('commentary', phase: 'commentary'),
    ];

    expect(
      codexTimelineCellsWithoutClaimedMatches(candidates, <CodexTimelineCell>[
        _cell('legacy'),
      ]),
      isEmpty,
    );
  });

  test('phase-less history preserves ambiguous explicit phases', () {
    final candidates = <CodexTimelineCell>[
      _cell('commentary', phase: 'commentary'),
      _cell('final', phase: 'final_answer'),
    ];

    expect(
      codexTimelineCellsWithoutClaimedMatches(candidates, <CodexTimelineCell>[
        _cell('legacy'),
      ]),
      candidates,
    );
  });

  test('ambiguous streaming prefixes do not claim a candidate', () {
    final candidates = <CodexTimelineCell>[
      _cell('short', text: 'Inspecting', streaming: true),
      _cell('long', text: 'Inspecting files', streaming: true),
    ];
    final replacements = <CodexTimelineCell>[
      _cell('modern', text: 'Inspecting files now'),
    ];

    expect(
      codexTimelineCellsWithoutClaimedMatches(candidates, replacements),
      candidates,
    );
  });

  test('a previously claimed prefix leaves one unique candidate', () {
    final candidates = <CodexTimelineCell>[
      _cell('exact', text: 'Inspecting files', streaming: true),
      _cell('prefix', text: 'Inspecting', streaming: true),
    ];
    final replacements = <CodexTimelineCell>[
      _cell('modern-exact', text: 'Inspecting files'),
      _cell('modern-prefix', text: 'Inspecting now'),
    ];

    expect(
      codexTimelineCellsWithoutClaimedMatches(candidates, replacements),
      isEmpty,
    );
  });

  test('text fallback only inspects the recent bounded window', () {
    final candidate = _cell('candidate', text: 'Old semantic match');
    final replacements = <CodexTimelineCell>[
      _cell('old-match', text: 'Old semantic match'),
      for (var index = 0; index < 1000; index += 1)
        _cell('history-$index', text: 'History $index'),
    ];

    expect(
      codexTimelineCellsWithoutClaimedMatches(<CodexTimelineCell>[
        candidate,
      ], replacements),
      <CodexTimelineCell>[candidate],
    );
  });

  test('exact identity still matches outside the text window', () {
    final candidate = _cell('old-exact');
    final replacements = <CodexTimelineCell>[
      _cell('old-exact'),
      for (var index = 0; index < 1000; index += 1)
        _cell('history-$index', text: 'History $index'),
    ];

    expect(
      codexTimelineCellsWithoutClaimedMatches(<CodexTimelineCell>[
        candidate,
      ], replacements),
      isEmpty,
    );
  });

  test('text fallback ignores candidate cells outside its bounded window', () {
    final oldCandidate = _cell('old-candidate', text: 'Old semantic match');
    final candidates = <CodexTimelineCell>[
      oldCandidate,
      for (var index = 0; index < 1000; index += 1)
        _cell('candidate-$index', text: 'Candidate $index'),
    ];

    expect(
      codexTimelineCellsWithoutClaimedMatches(candidates, <CodexTimelineCell>[
        _cell('replacement', text: 'Old semantic match'),
      ]),
      contains(oldCandidate),
    );
  });

  test('history predicates claim matching live candidates', () {
    final remaining = codexTimelineCellsWithoutClaimedMatches(
      <CodexTimelineCell>[
        _cell('history', text: 'History'),
        _cell('live', text: 'Live'),
      ],
      <CodexTimelineCell>[_cell('replacement', text: 'Replacement')],
      replacedByExactHistory: (candidate) => candidate.id == 'history',
    );

    expect(remaining.map((cell) => cell.id), <String>['live']);
  });

  test('history reconciliation recognizes canonical item identities', () {
    final candidate = _cell('legacy-live', itemId: 'shared');

    expect(
      codexTimelineCellsWithoutClaimedMatches(
        <CodexTimelineCell>[candidate],
        <CodexTimelineCell>[_cell('item-shared')],
        replacedByExactHistory: (_) => false,
      ),
      <CodexTimelineCell>[candidate],
    );
  });

  test('an exact replacement does not also claim repeated text', () {
    final duplicate = _cell('item-duplicate', text: 'Done');

    expect(
      codexTimelineCellsWithoutClaimedMatches(
        <CodexTimelineCell>[_cell('item-exact', text: 'Done'), duplicate],
        <CodexTimelineCell>[_cell('item-exact', text: 'Done')],
      ),
      <CodexTimelineCell>[duplicate],
    );
  });
}

CodexTimelineCell _cell(
  String id, {
  String? itemId,
  String? phase,
  String text = 'Same response',
  bool streaming = false,
}) => CodexTimelineCell.fromJson(<String, Object?>{
  'id': id,
  'itemId': ?itemId,
  'turnId': 'turn-1',
  'kind': 'assistantMessage',
  'status': 'completed',
  'markdownText': text,
  'isStreaming': streaming,
  'metadata': <String, Object?>{'streamPhase': ?phase},
});
