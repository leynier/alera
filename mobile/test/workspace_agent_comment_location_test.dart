import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment_location.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('workspaceAgentDiffLineAnchors', () {
    test('parses hunk headers and new-file line numbers', () {
      const lines = <MobileGitDiffLine>[
        MobileGitDiffLine(kind: 'hunk', text: '@@ -10,2 +12,3 @@ class Foo'),
        MobileGitDiffLine(kind: 'context', text: ' void start() {'),
        MobileGitDiffLine(kind: 'deletion', text: '-  old();'),
        MobileGitDiffLine(kind: 'addition', text: '+  next();'),
        MobileGitDiffLine(kind: 'addition', text: '+  extra();'),
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
      final anchors = workspaceAgentDiffLineAnchors(const <MobileGitDiffLine>[
        MobileGitDiffLine(kind: 'hunk', text: '@@ -1 +1 @@'),
        MobileGitDiffLine(kind: 'deletion', text: '-old'),
        MobileGitDiffLine(kind: 'addition', text: '+new'),
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
      const newFile = <MobileGitDiffLine>[
        MobileGitDiffLine(
          kind: 'header',
          text: 'diff --git a/lib/new.dart b/lib/new.dart',
        ),
        MobileGitDiffLine(kind: 'hunk', text: '@@ -0,0 +1,2 @@'),
        MobileGitDiffLine(kind: 'addition', text: '+one'),
        MobileGitDiffLine(kind: 'addition', text: '+two'),
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

      const deletedFile = <MobileGitDiffLine>[
        MobileGitDiffLine(kind: 'hunk', text: '@@ -4,2 +0,0 @@ class Gone'),
        MobileGitDiffLine(kind: 'deletion', text: '-old one'),
        MobileGitDiffLine(kind: 'deletion', text: '-old two'),
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
      const lines = <MobileGitDiffLine>[
        MobileGitDiffLine(kind: 'hunk', text: 'not a hunk header'),
        MobileGitDiffLine(kind: 'deletion', text: '-stale'),
        MobileGitDiffLine(kind: 'header', text: 'diff --git a/a.dart b/a.dart'),
        MobileGitDiffLine(kind: 'context', text: ' leftover'),
        MobileGitDiffLine(kind: 'addition', text: '+orphan'),
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
      const lines = <MobileGitDiffLine>[
        MobileGitDiffLine(kind: 'hunk', text: '@@ -1,1 +1,2 @@ first'),
        MobileGitDiffLine(kind: 'context', text: ' keep'),
        MobileGitDiffLine(kind: 'addition', text: '+added'),
        MobileGitDiffLine(kind: 'hunk', text: '@@ -8,1 +9,1 @@ second'),
        MobileGitDiffLine(kind: 'deletion', text: '-gone'),
        MobileGitDiffLine(kind: 'header', text: 'diff --git a/b.dart b/b.dart'),
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

  group('workspaceAgentCommentLocationLabel', () {
    test('joins path, area, hunk, and range', () {
      expect(
        workspaceAgentCommentLocationLabel(
          const WorkspaceAgentComment(
            id: '1',
            kind: WorkspaceAgentCommentKind.file,
            path: 'lib/a.dart',
            body: 'x',
          ),
        ),
        'lib/a.dart',
      );
      expect(
        workspaceAgentCommentLocationLabel(
          const WorkspaceAgentComment(
            id: '1',
            kind: WorkspaceAgentCommentKind.diff,
            path: 'lib/a.dart',
            body: 'x',
            areaLabel: 'Unstaged',
            hunkHeader: '@@ -1 +1 @@',
            lineRange: WorkspaceAgentCommentLineRange(startLine: 4, endLine: 4),
          ),
        ),
        'lib/a.dart · (Unstaged) · @@ -1 +1 @@ · line 4',
      );
    });

    test('formats area keys like desktop GitChangeArea labels', () {
      expect(workspaceAgentCommentAreaLabel('unstaged'), 'Unstaged');
      expect(workspaceAgentCommentAreaLabel('staged'), 'Staged');
      expect(workspaceAgentCommentAreaLabel('untracked'), 'Untracked');
    });
  });
}
