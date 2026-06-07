import 'package:alera/src/features/workbench/application/workspace_search_controller.dart';
import 'package:alera/src/features/workbench/presentation/workspace_search_panel.dart';
import 'package:alera/src/rust/api/workspace_search.dart' as native;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('replace conflict message reports partial replacement', () {
    final message = workspaceSearchReplaceConflictMessage(
      const native.WorkspaceReplaceResult(
        filesChanged: 1,
        matchesReplaced: 2,
        conflicts: <native.WorkspaceReplaceConflict>[
          native.WorkspaceReplaceConflict(
            relativePath: 'b.txt',
            reason: 'File was not part of the preview',
          ),
        ],
      ),
    );

    expect(
      message,
      'Replaced 2 matches. 1 file skipped. b.txt: File was not part of the preview',
    );
  });

  test('replace conflict message reports skipped replacement', () {
    final message = workspaceSearchReplaceConflictMessage(
      const native.WorkspaceReplaceResult(
        filesChanged: 0,
        matchesReplaced: 0,
        conflicts: <native.WorkspaceReplaceConflict>[
          native.WorkspaceReplaceConflict(
            relativePath: 'a.txt',
            reason: 'File changed on disk',
          ),
          native.WorkspaceReplaceConflict(
            relativePath: 'b.txt',
            reason: 'File was not part of the preview',
          ),
        ],
      ),
    );

    expect(message, 'Replace skipped 2 files. a.txt: File changed on disk');
  });

  test('replace conflict message counts each skipped file once', () {
    final message = workspaceSearchReplaceConflictMessage(
      const native.WorkspaceReplaceResult(
        filesChanged: 0,
        matchesReplaced: 0,
        conflicts: <native.WorkspaceReplaceConflict>[
          native.WorkspaceReplaceConflict(
            relativePath: 'a.txt',
            reason: 'Selected match is no longer available',
          ),
          native.WorkspaceReplaceConflict(
            relativePath: 'a.txt',
            reason: 'Selected match is no longer available',
          ),
        ],
      ),
    );

    expect(
      message,
      'Replace skipped 1 file. a.txt: Selected match is no longer available',
    );
  });

  test('replace conflict message is null without conflicts', () {
    expect(
      workspaceSearchReplaceConflictMessage(
        const native.WorkspaceReplaceResult(
          filesChanged: 1,
          matchesReplaced: 1,
          conflicts: <native.WorkspaceReplaceConflict>[],
        ),
      ),
      isNull,
    );
  });

  test('file replace is disabled when results are truncated', () {
    expect(
      workspaceSearchCanReplaceFile(
        const WorkspaceSearchState(query: 'needle', result: _searchResult),
      ),
      isTrue,
    );
    expect(
      workspaceSearchCanReplaceFile(
        const WorkspaceSearchState(
          query: 'needle',
          result: _truncatedSearchResult,
        ),
      ),
      isFalse,
    );
  });

  test('search text range maps non-bmp characters before the match', () {
    final range = workspaceSearchTextRangeForCharRange(
      text: '🙂needle',
      oneBasedColumn: 2,
      charLength: 6,
    );

    expect(range.start, 2);
    expect(range.end, 8);
  });

  test('search text range maps non-bmp characters inside the match', () {
    final range = workspaceSearchTextRangeForCharRange(
      text: 'a🙂b',
      oneBasedColumn: 2,
      charLength: 1,
    );

    expect(range.start, 1);
    expect(range.end, 3);
  });

  test('search text range uses display columns for clamped previews', () {
    final range = workspaceSearchTextRangeForCharRange(
      text: '…needle…',
      oneBasedColumn: 2,
      charLength: 6,
    );

    expect(range.start, 1);
    expect(range.end, 7);
  });
}

const native.WorkspaceSearchResult _searchResult = native.WorkspaceSearchResult(
  totalMatches: 1,
  truncated: false,
  files: <native.WorkspaceSearchFileResult>[
    native.WorkspaceSearchFileResult(
      relativePath: 'lib/main.dart',
      contentToken: 'token',
      matches: <native.WorkspaceSearchMatch>[
        native.WorkspaceSearchMatch(
          id: 'lib/main.dart:1:1:0',
          line: 1,
          column: 1,
          matchLength: 6,
          lineContent: 'needle',
        ),
      ],
    ),
  ],
);

const native.WorkspaceSearchResult _truncatedSearchResult =
    native.WorkspaceSearchResult(
      totalMatches: 1,
      truncated: true,
      files: <native.WorkspaceSearchFileResult>[
        native.WorkspaceSearchFileResult(
          relativePath: 'lib/main.dart',
          contentToken: 'token',
          matches: <native.WorkspaceSearchMatch>[
            native.WorkspaceSearchMatch(
              id: 'lib/main.dart:1:1:0',
              line: 1,
              column: 1,
              matchLength: 6,
              lineContent: 'needle',
            ),
          ],
        ),
      ],
    );
