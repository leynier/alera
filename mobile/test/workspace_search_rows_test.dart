import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workbench/domain/workspace_search_rows.dart';
import 'package:flutter_test/flutter_test.dart';

MobileWorkspaceSearchMatch _match(String path, int line, {int column = 1}) =>
    MobileWorkspaceSearchMatch(
      id: '$path:$line:$column:0',
      line: line,
      column: column,
      matchLength: 3,
      lineContent: 'foo bar',
    );

const _result = MobileWorkspaceSearchResult(
  totalMatches: 3,
  files: <MobileWorkspaceSearchFile>[
    MobileWorkspaceSearchFile(
      relativePath: 'lib/src/a.dart',
      matches: <MobileWorkspaceSearchMatch>[
        MobileWorkspaceSearchMatch(
          id: 'lib/src/a.dart:1:1:0',
          line: 1,
          column: 1,
          matchLength: 3,
          lineContent: 'foo',
        ),
        MobileWorkspaceSearchMatch(
          id: 'lib/src/a.dart:2:1:1',
          line: 2,
          column: 1,
          matchLength: 3,
          lineContent: 'foo',
        ),
      ],
    ),
    MobileWorkspaceSearchFile(
      relativePath: 'readme.md',
      matches: <MobileWorkspaceSearchMatch>[
        MobileWorkspaceSearchMatch(
          id: 'readme.md:1:1:0',
          line: 1,
          column: 1,
          matchLength: 3,
          lineContent: 'foo',
        ),
      ],
    ),
  ],
);

String _describe(WorkspaceSearchRow row) => switch (row) {
  WorkspaceSearchDirectoryRow(:final path, :final depth, :final matchCount) =>
    'dir $path d$depth ($matchCount)',
  WorkspaceSearchFileRow(:final file, :final depth) =>
    'file ${file.relativePath} d$depth',
  WorkspaceSearchMatchRow(:final match, :final depth) =>
    'match ${match.line} d$depth',
};

void main() {
  test('list view emits each file with its matches', () {
    final rows = workspaceSearchRows(
      _result,
      collapsedNodeKeys: const <String>{},
      viewAsTree: false,
    ).map(_describe);

    expect(rows, <String>[
      'file lib/src/a.dart d0',
      'match 1 d1',
      'match 2 d1',
      'file readme.md d0',
      'match 1 d1',
    ]);
  });

  test('tree view nests files under directories with match counts', () {
    final rows = workspaceSearchRows(
      _result,
      collapsedNodeKeys: const <String>{},
      viewAsTree: true,
    ).map(_describe);

    expect(rows, <String>[
      'dir lib d0 (2)',
      'dir lib/src d1 (2)',
      'file lib/src/a.dart d2',
      'match 1 d3',
      'match 2 d3',
      'file readme.md d0',
      'match 1 d1',
    ]);
  });

  test('collapsed nodes hide their descendants', () {
    final rows = workspaceSearchRows(
      _result,
      collapsedNodeKeys: <String>{
        workspaceSearchDirectoryNodeKey('lib'),
        workspaceSearchFileNodeKey('readme.md'),
      },
      viewAsTree: true,
    ).map(_describe);

    expect(rows, <String>['dir lib d0 (2)', 'file readme.md d0']);
  });

  test('collapsible keys include directories only in tree view', () {
    expect(
      workspaceSearchCollapsibleNodeKeys(_result, viewAsTree: false),
      <String>{'file:lib/src/a.dart', 'file:readme.md'},
    );
    expect(
      workspaceSearchCollapsibleNodeKeys(_result, viewAsTree: true),
      <String>{
        'dir:lib',
        'dir:lib/src',
        'file:lib/src/a.dart',
        'file:readme.md',
      },
    );
  });

  test('match range counts characters, not UTF-16 code units', () {
    const match = MobileWorkspaceSearchMatch(
      id: 'a:1:3:0',
      line: 1,
      column: 3,
      matchLength: 3,
      lineContent: '😀 foo',
    );
    final range = workspaceSearchMatchRange(match, match.lineContent);

    expect(match.lineContent.substring(range.start, range.end), 'foo');
  });

  test('match range prefers the elided display column', () {
    final match = MobileWorkspaceSearchMatch(
      id: 'a:1:900:0',
      line: 1,
      column: 900,
      matchLength: 3,
      lineContent: '…xx foo',
      displayColumn: 5,
      displayMatchLength: 3,
    );
    final range = workspaceSearchMatchRange(match, match.lineContent);

    expect(match.lineContent.substring(range.start, range.end), 'foo');
  });

  test('conflict message matches the desktop wording', () {
    expect(
      workspaceSearchReplaceConflictMessage(
        const MobileWorkspaceReplaceResult(matchesReplaced: 2),
      ),
      isNull,
    );
    expect(
      workspaceSearchReplaceConflictMessage(
        const MobileWorkspaceReplaceResult(
          matchesReplaced: 2,
          conflicts: <MobileWorkspaceReplaceConflict>[
            MobileWorkspaceReplaceConflict(
              relativePath: 'a.dart',
              reason: 'File changed on disk',
            ),
          ],
        ),
      ),
      'Replaced 2 matches. 1 file skipped. a.dart: File changed on disk',
    );
    expect(
      workspaceSearchReplaceConflictMessage(
        const MobileWorkspaceReplaceResult(
          conflicts: <MobileWorkspaceReplaceConflict>[
            MobileWorkspaceReplaceConflict(relativePath: 'a', reason: 'x'),
            MobileWorkspaceReplaceConflict(relativePath: 'b', reason: 'y'),
          ],
        ),
      ),
      'Replace skipped 2 files. a: x',
    );
  });

  test('parses replace payload fields', () {
    final file = MobileWorkspaceSearchFile.fromJson(const <String, Object?>{
      'relativePath': 'a.dart',
      'contentToken': '12:34',
      'matches': <Object?>[
        <String, Object?>{
          'id': 'a.dart:1:1:0',
          'line': 1,
          'column': 1,
          'matchLength': 3,
          'lineContent': 'foo',
          'displayColumn': null,
          'replacementPreview': 'bar',
        },
      ],
    });
    expect(file.contentToken, '12:34');
    expect(file.matches.single.replacementPreview, 'bar');
    expect(file.matches.single.displayColumn, isNull);
    final replaced = MobileWorkspaceReplaceResult.fromJson(
      const <String, Object?>{
        'filesChanged': 1,
        'matchesReplaced': 2,
        'conflicts': <Object?>[
          <String, Object?>{'relativePath': 'b', 'reason': 'gone'},
        ],
      },
    );
    expect(replaced.filesChanged, 1);
    expect(replaced.conflicts.single.reason, 'gone');
    expect(_match('x', 1).id, 'x:1:1:0');
  });
}
