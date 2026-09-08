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
