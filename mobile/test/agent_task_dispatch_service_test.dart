import 'dart:convert';

import 'package:alera_mobile/src/features/agent_task_dispatch/application/agent_task_dispatch_service.dart';
import 'package:alera_mobile/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment_target.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_terminal_client.dart';

void main() {
  late FakeTerminalClient client;
  late AgentTaskDispatchService service;

  setUp(() {
    client = FakeTerminalClient()
      ..tabs = [fakeTab(id: 'tab-1', title: 'Codex')];
    service = AgentTaskDispatchService(
      workspaceId: 'workspace-1',
      terminalClient: client,
      launchProfile: (profileId, prompt) async {
        return client
            .launchAgentProfile(
              workspaceId: 'workspace-1',
              profileId: profileId,
              prompt: prompt,
              clientMutationId: 'test',
            )
            .then((launch) => launch.tabId);
      },
      tabs: () => client.tabs,
      runningAgents: () => client.agentPresence,
    );
  });

  tearDown(() => client.dispose());

  test('writes to a running tab with a deferred Enter', () async {
    final result = await service.dispatchTarget(
      const RunningAgentCommentTarget(
        AgentPresenceSummary(
          terminalSessionId: 'session-tab-1',
          workspaceId: 'workspace-1',
          tabId: 'tab-1',
          agentType: 'codex',
          state: 'waiting',
          title: 'Codex',
        ),
      ),
      'Pull request #42 checks failed. Please fix them.',
    );
    expect(result.openedNewTab, isFalse);
    expect(result.tabId, 'tab-1');
    expect(utf8.decode(client.writes.single), contains('checks failed'));
    expect(
      client.calls.singleWhere((call) => call.startsWith('write')),
      contains('enter=true'),
    );
  });

  test('launches a profile when the bound tab is gone', () async {
    client.tabs = [];
    final result = await service.dispatchBinding(
      const AgentTaskDispatchBinding(
        tabId: 'gone',
        profileId: 'profile-1',
        label: 'Codex',
      ),
      pullRequestPrompt,
    );
    expect(result.openedNewTab, isTrue);
    expect(result.tabId, 'agent-tab');
    expect(
      client.calls.singleWhere((call) => call.startsWith('launchAgentProfile')),
      contains(pullRequestPrompt),
    );
  });

  test('refuses an empty prompt', () async {
    await expectLater(
      service.dispatchBinding(
        const AgentTaskDispatchBinding(tabId: 'tab-1'),
        '  ',
      ),
      throwsA(isA<AgentTaskDispatchException>()),
    );
  });
}

const pullRequestPrompt = 'Pull request #42 checks failed. Please fix them.';
