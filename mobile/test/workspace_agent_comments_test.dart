import 'dart:convert';

import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/terminal/application/tabs_controller.dart';
import 'package:alera_mobile/src/features/terminal/application/terminal_providers.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/application/workspace_agent_comment_controller.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment_prompt.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment_target.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

void main() {
  test('builds the same prompt as the desktop comment queue', () {
    final prompt = workspaceAgentCommentPrompt(const <WorkspaceAgentComment>[
      WorkspaceAgentComment(id: '1', path: 'lib/main.dart', body: 'Rename x'),
      WorkspaceAgentComment(id: '2', path: 'readme.md', body: '   '),
      WorkspaceAgentComment(
        id: '3',
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
            path: 'lib/main.dart',
            body: 'Rename x',
          ),
        ]),
      );
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
