import 'dart:convert';

import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/terminal/application/tabs_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/application/workspace_agent_comment_controller.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment_location.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment_prompt.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment_target.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

void main() {
  test('builds the same prompt as the desktop comment queue', () {
    final prompt = workspaceAgentCommentPrompt(const <WorkspaceAgentComment>[
      WorkspaceAgentComment(
        id: '1',
        kind: WorkspaceAgentCommentKind.file,
        path: 'lib/main.dart',
        body: 'Rename x',
      ),
      WorkspaceAgentComment(
        id: '2',
        kind: WorkspaceAgentCommentKind.file,
        path: 'readme.md',
        body: '   ',
      ),
      WorkspaceAgentComment(
        id: '3',
        kind: WorkspaceAgentCommentKind.file,
        path: 'docs/a.md',
        body: 'Fix the typo',
        snippet: 'teh',
      ),
    ]);
    expect(
      prompt,
      'Please act on these comments in the current workspace.\n\n'
      '## 1. File `lib/main.dart`\nComment:\nRename x\n\n'
      '## 3. File `docs/a.md`\n```\nteh\n```\nComment:\nFix the typo',
    );
    expect(workspaceAgentCommentPrompt(const <WorkspaceAgentComment>[]), '');
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

    expect(
      prompt,
      'Please act on these comments in the current workspace.\n\n'
      '## 1. File `lib/a.dart` lines 12-18\n'
      '```\n'
      'void start() {}\n'
      '```\n'
      'Comment:\n'
      'Extract this helper.\n\n'
      '## 2. Diff `lib/b.dart` (Unstaged) hunk `@@ -10,6 +12,8 @@ class Bar` lines 12-14\n'
      '```\n'
      '+  return null;\n'
      '```\n'
      'Comment:\n'
      'This looks wrong.',
    );
  });

  test('labels deletion-only diff anchors as old-side lines', () {
    const lines = <MobileGitDiffLine>[
      MobileGitDiffLine(kind: 'hunk', text: '@@ -4,2 +0,0 @@ class Gone'),
      MobileGitDiffLine(kind: 'deletion', text: '-old one'),
    ];
    final anchor = workspaceAgentDiffLineAnchors(lines)[1];
    final prompt = workspaceAgentCommentPrompt(<WorkspaceAgentComment>[
      WorkspaceAgentComment(
        id: '1',
        kind: WorkspaceAgentCommentKind.diff,
        path: 'lib/gone.dart',
        body: 'Keep this helper elsewhere before deleting it.',
        hunkHeader: anchor.hunkHeader,
        lineRange: workspaceAgentCommentRangeForDiffAnchor(anchor),
        snippet: workspaceAgentCommentSnippetForDiffAnchor(
          lines: lines,
          anchor: anchor,
        ),
      ),
    ]);
    expect(
      prompt,
      contains(
        '## 1. Diff `lib/gone.dart` hunk `@@ -4,2 +0,0 @@ class Gone` old line 4',
      ),
    );
    expect(prompt, contains('-old one'));
    expect(
      workspaceAgentCommentLocationLabel(
        WorkspaceAgentComment(
          id: '1',
          kind: WorkspaceAgentCommentKind.diff,
          path: 'lib/gone.dart',
          body: 'x',
          hunkHeader: anchor.hunkHeader,
          lineRange: workspaceAgentCommentRangeForDiffAnchor(anchor),
        ),
      ),
      'lib/gone.dart · @@ -4,2 +0,0 @@ class Gone · old line 4',
    );
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

  group('sending queued comments', () {
    late FakeTerminalClient client;
    late ProviderContainer container;

    setUp(() {
      client = FakeTerminalClient();
      container = ProviderContainer(
        overrides: [
          terminalClientProvider('host-1').overrideWith((ref) async => client),
          workspaceClientProvider('host-1').overrideWith((ref) async => client),
        ],
      );
      // Keep the tabs controller alive the way the workspace screen does.
      container.listen(
        tabsControllerProvider('host-1', 'workspace-1'),
        (_, _) {},
      );
    });

    tearDown(() async {
      container.dispose();
      await client.dispose();
    });

    WorkspaceAgentCommentController queue() => container.read(
      workspaceAgentCommentControllerProvider('host-1', 'workspace-1').notifier,
    );

    List<WorkspaceAgentComment> queued() => container.read(
      workspaceAgentCommentControllerProvider('host-1', 'workspace-1'),
    );

    test('writes to a running agent with a deferred Enter', () async {
      queue()
        ..add(path: 'lib/main.dart', body: 'Rename x')
        ..add(path: 'readme.md', body: '  ');
      expect(queued(), hasLength(1));

      final tabId = await queue().sendTo(
        const RunningAgentCommentTarget(
          AgentPresenceSummary(
            terminalSessionId: 'session-agent',
            workspaceId: 'workspace-1',
            tabId: 'tab-agent',
            agentType: 'codex',
            state: 'waiting',
          ),
        ),
      );

      expect(tabId, 'tab-agent');
      final write = client.calls.singleWhere(
        (call) => call.startsWith('write '),
      );
      expect(write, startsWith('write session-agent '));
      expect(write, endsWith('paste=true enter=true'));
      expect(
        utf8.decode(client.writes.single),
        workspaceAgentCommentPrompt(const <WorkspaceAgentComment>[
          WorkspaceAgentComment(
            id: '',
            kind: WorkspaceAgentCommentKind.file,
            path: 'lib/main.dart',
            body: 'Rename x',
          ),
        ]),
      );
      expect(queued(), isEmpty);
    });

    test('keeps file comments when a diff comment joins the queue', () async {
      queue()
        ..add(path: 'lib/main.dart', body: 'Rename x')
        ..add(
          path: 'lib/b.dart',
          body: 'This looks wrong.',
          kind: WorkspaceAgentCommentKind.diff,
          areaLabel: 'Unstaged',
          hunkHeader: '@@ -10,6 +12,8 @@ class Bar',
          lineRange: const WorkspaceAgentCommentLineRange(
            startLine: 13,
            endLine: 13,
          ),
          snippet: '+  next();',
        );
      expect(queued(), hasLength(2));
      expect(queued().first.kind, WorkspaceAgentCommentKind.file);
      expect(queued().last.kind, WorkspaceAgentCommentKind.diff);

      final tabId = await queue().sendTo(
        const AgentProfileCommentTarget(
          AgentProfileSummary(
            id: 'profile-1',
            name: 'Codex',
            agentType: 'codex',
          ),
        ),
      );

      expect(tabId, 'agent-tab');
      final launch = client.calls.singleWhere(
        (call) => call.startsWith('launchAgentProfile'),
      );
      expect(launch, contains('File `lib/main.dart`'));
      expect(launch, contains('Diff `lib/b.dart` (Unstaged)'));
      expect(queued(), isEmpty);
    });

    test('opens a profile tab with the prompt', () async {
      queue().add(path: 'lib/main.dart', body: 'Rename x');

      final tabId = await queue().sendTo(
        const AgentProfileCommentTarget(
          AgentProfileSummary(
            id: 'profile-1',
            name: 'Codex',
            agentType: 'codex',
          ),
        ),
      );

      expect(tabId, 'agent-tab');
      expect(
        client.calls.where((call) => call.startsWith('launchAgentProfile ')),
        hasLength(1),
      );
      expect(
        client.calls.singleWhere(
          (call) => call.startsWith('launchAgentProfile'),
        ),
        contains('File `lib/main.dart`'),
      );
      expect(queued(), isEmpty);
    });

    test('keeps the queue when the host rejects the write', () async {
      client.writeErrors.add(StateError('Terminal session is not attached.'));
      queue().add(path: 'lib/main.dart', body: 'Rename x');

      await expectLater(
        queue().sendTo(
          const RunningAgentCommentTarget(
            AgentPresenceSummary(
              terminalSessionId: 'session-gone',
              workspaceId: 'workspace-1',
              tabId: 'tab-gone',
              agentType: 'codex',
              state: 'done',
            ),
          ),
        ),
        throwsStateError,
      );
      expect(queued(), hasLength(1));
    });

    test('refuses to send an empty queue', () async {
      await expectLater(
        queue().sendTo(
          const AgentProfileCommentTarget(
            AgentProfileSummary(
              id: 'profile-1',
              name: 'Codex',
              agentType: 'codex',
            ),
          ),
        ),
        throwsStateError,
      );
      expect(client.calls.where((call) => call.startsWith('launch')), isEmpty);
    });
  });
}
