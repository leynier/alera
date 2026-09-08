import 'package:alera/src/features/workspace_agent_comments/application/workspace_agent_comment_controller.dart';
import 'package:alera/src/features/workspace_agent_comments/domain/workspace_agent_comment.dart';
import 'package:alera/src/features/workspace_agent_comments/domain/workspace_agent_comment_prompt.dart';
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
      expect(capWorkspaceAgentCommentSnippet('a\r\nb\r\n'), 'a\nb');
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
        const WorkspaceAgentCommentLineRange(startLine: 4, endLine: 6),
        isNot(const WorkspaceAgentCommentLineRange(startLine: 4, endLine: 5)),
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

      controller.remove('missing');
      expect(container.read(provider), hasLength(2));
      controller.remove('a');
      expect(container.read(provider).single.id, 'b');

      controller.clear();
      expect(container.read(provider), isEmpty);
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
