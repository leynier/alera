import 'package:alera/src/features/workspace_agent_comments/application/workspace_agent_comment_controller.dart';
import 'package:alera/src/features/workspace_agent_comments/domain/workspace_agent_comment.dart';
import 'package:alera/src/features/workspace_agent_comments/domain/workspace_agent_comment_location.dart';
import 'package:alera/src/features/workspace_agent_comments/domain/workspace_agent_comment_prompt.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('workspaceAgentCommentPrompt', () {
    test('returns empty when there are no comments with a body', () {
      expect(workspaceAgentCommentPrompt(const <WorkspaceAgentComment>[]), '');
      expect(
        workspaceAgentCommentPrompt(const <WorkspaceAgentComment>[
          WorkspaceAgentComment(
            id: '1',
            kind: WorkspaceAgentCommentKind.file,
            path: 'lib/a.dart',
            body: '   ',
          ),
        ]),
        '',
      );
    });

    test('batches file and diff comments with path, range, and hunk', () {
      final prompt = workspaceAgentCommentPrompt(const <WorkspaceAgentComment>[
        WorkspaceAgentComment(
          id: '1',
          kind: WorkspaceAgentCommentKind.file,
          path: 'lib/a.dart',
          body: 'Extract this helper.',
          lineRange: WorkspaceAgentCommentLineRange(startLine: 12, endLine: 18),
          snippet: 'void start() {}',
        ),
        WorkspaceAgentComment(
          id: '2',
          kind: WorkspaceAgentCommentKind.diff,
          path: 'lib/b.dart',
          body: 'This looks wrong.',
          areaLabel: 'Unstaged',
          hunkHeader: '@@ -10,6 +12,8 @@ class Bar',
          lineRange: WorkspaceAgentCommentLineRange(startLine: 12, endLine: 14),
          snippet: '+  return null;',
        ),
      ]);

      expect(prompt, contains('Please act on these comments'));
      expect(prompt, contains('## 1. File `lib/a.dart` lines 12-18'));
      expect(prompt, contains('void start() {}'));
      expect(prompt, contains('Extract this helper.'));
      expect(
        prompt,
        contains(
          '## 2. Diff `lib/b.dart` (Unstaged) hunk `@@ -10,6 +12,8 @@ class Bar` lines 12-14',
        ),
      );
      expect(prompt, contains('+  return null;'));
      expect(prompt, contains('This looks wrong.'));
    });

    test('omits blank area, hunk, range, and snippet from a file comment', () {
      final prompt = workspaceAgentCommentPrompt(const <WorkspaceAgentComment>[
        WorkspaceAgentComment(
          id: '1',
          kind: WorkspaceAgentCommentKind.file,
          path: 'lib/a.dart',
          body: 'Look here.',
          areaLabel: '  ',
          hunkHeader: ' ',
        ),
      ]);
      expect(prompt, contains('## 1. File `lib/a.dart`'));
      expect(prompt, isNot(contains('hunk')));
      expect(prompt, isNot(contains('```')));
      expect(prompt, contains('Comment:\nLook here.'));
    });
  });

  group('workspaceAgentCommentDispatchRequest', () {
    test('returns null for empty comments', () {
      expect(
        workspaceAgentCommentDispatchRequest(
          workspaceId: 'workspace-1',
          comments: const <WorkspaceAgentComment>[],
        ),
        isNull,
      );
    });

    test('builds a shared dispatch request for a comment batch', () {
      final request = workspaceAgentCommentDispatchRequest(
        workspaceId: 'workspace-1',
        comments: const <WorkspaceAgentComment>[
          WorkspaceAgentComment(
            id: '1',
            kind: WorkspaceAgentCommentKind.file,
            path: 'lib/a.dart',
            body: 'Fix this.',
          ),
          WorkspaceAgentComment(
            id: '2',
            kind: WorkspaceAgentCommentKind.diff,
            path: 'lib/b.dart',
            body: 'And this.',
            areaLabel: 'Staged',
          ),
        ],
      );

      expect(request, isNotNull);
      expect(request!.workspaceId, 'workspace-1');
      expect(request.title, 'Send Comments to Agent');
      expect(request.prompt, contains('lib/a.dart'));
      expect(request.prompt, contains('lib/b.dart'));
      expect(
        request.message,
        contains('These 2 comments will be sent together'),
      );
    });

    test('uses the single-comment dispatch copy', () {
      final request = workspaceAgentCommentDispatchRequest(
        workspaceId: 'workspace-1',
        comments: const <WorkspaceAgentComment>[
          WorkspaceAgentComment(
            id: '1',
            kind: WorkspaceAgentCommentKind.file,
            path: 'lib/a.dart',
            body: 'Fix this.',
          ),
        ],
      );
      expect(
        request!.message,
        'Choose a running agent or open a new tab from a profile.',
      );
    });
  });

  group('capWorkspaceAgentCommentSnippet', () {
    test('returns null for missing or blank snippets', () {
      expect(capWorkspaceAgentCommentSnippet(null), isNull);
      expect(capWorkspaceAgentCommentSnippet('   '), isNull);
      expect(capWorkspaceAgentCommentSnippet('\r\n\r\n'), isNull);
    });

    test('caps long snippets by line count and character count', () {
      final manyLines = List<String>.generate(
        workspaceAgentCommentMaxSnippetLines + 2,
        (index) => 'line $index',
      ).join('\n');
      final cappedLines = capWorkspaceAgentCommentSnippet(manyLines)!;
      expect(
        cappedLines.split('\n'),
        hasLength(workspaceAgentCommentMaxSnippetLines + 1),
      );
      expect(cappedLines, endsWith('...'));

      final long = 'a' * (workspaceAgentCommentMaxSnippetChars + 8);
      final cappedChars = capWorkspaceAgentCommentSnippet(long)!;
      expect(cappedChars.length, workspaceAgentCommentMaxSnippetChars + 3);
      expect(cappedChars, endsWith('...'));
    });
  });

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
      expect(anchors[3].newLine, 13);
      expect(anchors[4].newLine, 14);
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
      expect(removed[2].oldLine, 5);
      expect(
        workspaceAgentCommentRangeForDiffAnchor(removed[1]),
        const WorkspaceAgentCommentLineRange(startLine: 4, endLine: 4),
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
            areaLabel: '  ',
            hunkHeader: '   ',
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

    test('formats single and multi line ranges', () {
      expect(
        const WorkspaceAgentCommentLineRange(
          startLine: 4,
          endLine: 4,
        ).isSingleLine,
        isTrue,
      );
      expect(
        const WorkspaceAgentCommentLineRange(startLine: 4, endLine: 4).label,
        'line 4',
      );
      expect(
        const WorkspaceAgentCommentLineRange(startLine: 4, endLine: 6).hashCode,
        const WorkspaceAgentCommentLineRange(startLine: 4, endLine: 6).hashCode,
      );
    });
  });

  group('WorkspaceAgentCommentController', () {
    test('adds, removes, and clears workspace comments', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final provider = workspaceAgentCommentControllerProvider('workspace-1');
      final controller = container.read(provider.notifier);

      controller.add(
        const WorkspaceAgentComment(
          id: 'a',
          kind: WorkspaceAgentCommentKind.file,
          path: 'lib/a.dart',
          body: '  Fix this.  ',
        ),
      );
      controller.add(
        const WorkspaceAgentComment(
          id: 'b',
          kind: WorkspaceAgentCommentKind.diff,
          path: 'lib/b.dart',
          body: 'And this.',
          areaLabel: 'Unstaged',
        ),
      );
      expect(container.read(provider), hasLength(2));
      expect(container.read(provider).first.body, 'Fix this.');

      controller.remove('a');
      expect(container.read(provider).single.id, 'b');

      controller.clear();
      expect(container.read(provider), isEmpty);
    });

    test('ignores empty comment bodies', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final provider = workspaceAgentCommentControllerProvider('workspace-1');
      container
          .read(provider.notifier)
          .add(
            const WorkspaceAgentComment(
              id: 'a',
              kind: WorkspaceAgentCommentKind.file,
              path: 'lib/a.dart',
              body: '   ',
            ),
          );
      expect(container.read(provider), isEmpty);
    });
  });
}
