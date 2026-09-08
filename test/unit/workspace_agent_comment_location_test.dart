import 'package:alera/src/features/workspace_agent_comments/domain/workspace_agent_comment.dart';
import 'package:alera/src/features/workspace_agent_comments/domain/workspace_agent_comment_location.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('workspaceAgentCommentLineRangeForSelection', () {
    const text = 'one\ntwo\nthree';

    test('maps a collapsed caret to its line', () {
      expect(
        workspaceAgentCommentLineRangeForSelection(
          text: text,
          selection: const TextSelection.collapsed(offset: 0),
        ),
        const WorkspaceAgentCommentLineRange(startLine: 1, endLine: 1),
      );
      expect(
        workspaceAgentCommentLineRangeForSelection(
          text: text,
          selection: const TextSelection.collapsed(offset: 4),
        ),
        const WorkspaceAgentCommentLineRange(startLine: 2, endLine: 2),
      );
    });

    test('maps a range that spans lines', () {
      expect(
        workspaceAgentCommentLineRangeForSelection(
          text: text,
          selection: const TextSelection(baseOffset: 0, extentOffset: 7),
        ),
        const WorkspaceAgentCommentLineRange(startLine: 1, endLine: 2),
      );
    });

    test('captures selected snippet text', () {
      expect(
        workspaceAgentCommentSnippetForSelection(
          text: text,
          selection: const TextSelection(baseOffset: 4, extentOffset: 7),
        ),
        'two',
      );
    });

    test('returns null for empty text', () {
      expect(
        workspaceAgentCommentLineRangeForSelection(
          text: '',
          selection: const TextSelection.collapsed(offset: 0),
        ),
        isNull,
      );
      expect(
        workspaceAgentCommentSnippetForSelection(
          text: '',
          selection: const TextSelection.collapsed(offset: 0),
        ),
        isNull,
      );
    });

    test('uses an invalid or inverted selection', () {
      expect(
        workspaceAgentCommentLineRangeForSelection(
          text: text,
          selection: const TextSelection(baseOffset: -1, extentOffset: -1),
        ),
        const WorkspaceAgentCommentLineRange(startLine: 1, endLine: 1),
      );
      expect(
        workspaceAgentCommentLineRangeForSelection(
          text: text,
          selection: const TextSelection(baseOffset: 13, extentOffset: 4),
        ),
        const WorkspaceAgentCommentLineRange(startLine: 2, endLine: 3),
      );
      expect(
        workspaceAgentCommentSnippetForSelection(
          text: text,
          selection: const TextSelection(baseOffset: -1, extentOffset: -1),
        ),
        'one',
      );
      expect(
        workspaceAgentCommentSnippetForSelection(
          text: text,
          selection: const TextSelection.collapsed(offset: 5),
        ),
        'two',
      );
      expect(
        workspaceAgentCommentSnippetForSelection(
          text: text,
          selection: const TextSelection(baseOffset: 13, extentOffset: 4),
        ),
        'two\nthree',
      );
    });

    test('reads the line under a caret at a newline or past the end', () {
      expect(
        workspaceAgentCommentSnippetForSelection(
          text: text,
          selection: const TextSelection.collapsed(offset: 0),
        ),
        'one',
      );
      expect(
        workspaceAgentCommentSnippetForSelection(
          text: text,
          selection: const TextSelection.collapsed(offset: 3),
        ),
        'one',
      );
      expect(
        workspaceAgentCommentSnippetForSelection(
          text: text,
          selection: const TextSelection.collapsed(offset: 13),
        ),
        'three',
      );
      expect(
        workspaceAgentCommentSnippetForSelection(
          text: text,
          selection: const TextSelection.collapsed(offset: 99),
        ),
        'three',
      );
      expect(
        workspaceAgentCommentSnippetForSelection(
          text: 'one\n',
          selection: const TextSelection.collapsed(offset: 4),
        ),
        isNull,
      );
    });

    test('returns null when a selection clamps to empty', () {
      expect(
        workspaceAgentCommentSnippetForSelection(
          text: text,
          selection: const TextSelection(baseOffset: 80, extentOffset: 90),
        ),
        isNull,
      );
    });
  });

  group('workspaceAgentDiffLineAnchors', () {
    test('parses hunk headers and new-file line numbers', () {
      const lines = <GitDiffLine>[
        GitDiffLine.hunk('@@ -10,2 +12,3 @@ class Foo'),
        GitDiffLine.context(' void start() {'),
        GitDiffLine.deletion('-  old();'),
        GitDiffLine.addition('+  next();'),
        GitDiffLine.addition('+  extra();'),
      ];

      final anchors = workspaceAgentDiffLineAnchors(lines);
      expect(anchors, hasLength(5));
      expect(anchors[0].hunkHeader, '@@ -10,2 +12,3 @@ class Foo');
      expect(
        workspaceAgentCommentRangeForDiffAnchor(anchors[0]),
        const WorkspaceAgentCommentLineRange(startLine: 12, endLine: 14),
      );
      expect(anchors[2].oldLine, 11);
      expect(anchors[2].newLine, isNull);
      expect(
        workspaceAgentCommentRangeForDiffAnchor(anchors[2]),
        const WorkspaceAgentCommentLineRange(
          startLine: 11,
          endLine: 11,
          side: WorkspaceAgentCommentLineSide.oldSide,
        ),
      );
      expect(anchors[3].newLine, 13);
      expect(anchors[4].newLine, 14);
      expect(
        workspaceAgentCommentRangeForDiffAnchor(anchors[3]),
        const WorkspaceAgentCommentLineRange(startLine: 13, endLine: 13),
      );
      expect(
        workspaceAgentCommentSnippetForDiffAnchor(
          lines: lines,
          anchor: anchors[3],
        ),
        '+  next();',
      );
    });

    test('treats omitted hunk counts as one', () {
      final anchors = workspaceAgentDiffLineAnchors(const <GitDiffLine>[
        GitDiffLine.hunk('@@ -1 +1 @@'),
        GitDiffLine.deletion('-old'),
        GitDiffLine.addition('+new'),
      ]);
      expect(anchors[1].oldLine, 1);
      expect(anchors[2].newLine, 1);
      expect(
        workspaceAgentCommentRangeForDiffAnchor(anchors[1]),
        const WorkspaceAgentCommentLineRange(
          startLine: 1,
          endLine: 1,
          side: WorkspaceAgentCommentLineSide.oldSide,
        ),
      );
      expect(
        workspaceAgentCommentRangeForDiffAnchor(anchors[2]),
        const WorkspaceAgentCommentLineRange(startLine: 1, endLine: 1),
      );
    });

    test('anchors old-side deletions and new-file / deleted-file hunks', () {
      const newFile = <GitDiffLine>[
        GitDiffLine.header('diff --git a/lib/new.dart b/lib/new.dart'),
        GitDiffLine.hunk('@@ -0,0 +1,2 @@'),
        GitDiffLine.addition('+one'),
        GitDiffLine.addition('+two'),
      ];
      final created = workspaceAgentDiffLineAnchors(newFile);
      expect(created[0].hunkHeader, isNull);
      expect(workspaceAgentCommentRangeForDiffAnchor(created[0]), isNull);
      expect(created[1].hunkNewStart, 1);
      expect(created[1].hunkNewEnd, 2);
      expect(created[2].newLine, 1);
      expect(created[3].newLine, 2);
      expect(
        workspaceAgentCommentRangeForDiffAnchor(created[2]),
        const WorkspaceAgentCommentLineRange(startLine: 1, endLine: 1),
      );

      const deletedFile = <GitDiffLine>[
        GitDiffLine.hunk('@@ -4,2 +0,0 @@ class Gone'),
        GitDiffLine.deletion('-old one'),
        GitDiffLine.deletion('-old two'),
      ];
      final removed = workspaceAgentDiffLineAnchors(deletedFile);
      expect(removed[0].hunkNewStart, isNull);
      expect(removed[0].hunkNewEnd, isNull);
      expect(workspaceAgentCommentRangeForDiffAnchor(removed[0]), isNull);
      expect(removed[1].oldLine, 4);
      expect(removed[1].newLine, isNull);
      expect(removed[2].oldLine, 5);
      expect(
        workspaceAgentCommentRangeForDiffAnchor(removed[1]),
        const WorkspaceAgentCommentLineRange(
          startLine: 4,
          endLine: 4,
          side: WorkspaceAgentCommentLineSide.oldSide,
        ),
      );
      expect(
        workspaceAgentCommentRangeForDiffAnchor(removed[2]),
        const WorkspaceAgentCommentLineRange(
          startLine: 5,
          endLine: 5,
          side: WorkspaceAgentCommentLineSide.oldSide,
        ),
      );
      expect(
        workspaceAgentCommentRangeForDiffAnchor(removed[1])!.label,
        'old line 4',
      );
      expect(
        workspaceAgentCommentSnippetForDiffAnchor(
          lines: deletedFile,
          anchor: removed[1],
        ),
        '-old one',
      );
    });

    test('keeps unparsed hunk text and resets after a file header', () {
      const lines = <GitDiffLine>[
        GitDiffLine.hunk('not a hunk header'),
        GitDiffLine.deletion('-stale'),
        GitDiffLine.header('diff --git a/a.dart b/a.dart'),
        GitDiffLine.context(' leftover'),
        GitDiffLine.addition('+orphan'),
      ];
      final anchors = workspaceAgentDiffLineAnchors(lines);
      expect(anchors[0].hunkHeader, 'not a hunk header');
      expect(workspaceAgentCommentRangeForDiffAnchor(anchors[0]), isNull);
      expect(anchors[1].oldLine, isNull);
      expect(anchors[2].hunkHeader, isNull);
      expect(anchors[3].oldLine, isNull);
      expect(anchors[3].newLine, isNull);
      expect(anchors[4].newLine, isNull);
      expect(workspaceAgentCommentRangeForDiffAnchor(anchors[4]), isNull);
    });

    test('captures a hunk snippet until the next hunk or header', () {
      const lines = <GitDiffLine>[
        GitDiffLine.hunk('@@ -1,1 +1,2 @@ first'),
        GitDiffLine.context(' keep'),
        GitDiffLine.addition('+added'),
        GitDiffLine.hunk('@@ -8,1 +9,1 @@ second'),
        GitDiffLine.deletion('-gone'),
        GitDiffLine.header('diff --git a/b.dart b/b.dart'),
      ];
      final anchors = workspaceAgentDiffLineAnchors(lines);
      expect(
        workspaceAgentCommentSnippetForDiffAnchor(
          lines: lines,
          anchor: anchors[0],
        ),
        '@@ -1,1 +1,2 @@ first\n keep\n+added',
      );
      expect(
        workspaceAgentCommentSnippetForDiffAnchor(
          lines: lines,
          anchor: anchors[3],
        ),
        '@@ -8,1 +9,1 @@ second\n-gone',
      );
    });
  });
}
