import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_agent_run_groups.dart';
import 'package:flutter_test/flutter_test.dart';

AgentPresenceSummary _presence({
  required String state,
  String agentType = 'codex',
  bool? interrupted,
  String handle = 't1',
}) {
  return AgentPresenceSummary(
    terminalSessionId: handle,
    workspaceId: 'ws',
    tabId: 'tab-$handle',
    agentType: agentType,
    state: state,
    interrupted: interrupted,
  );
}

void main() {
  test('groups by state in attention-first order', () {
    final groups = groupWorkspaceAgentRuns(<AgentPresenceSummary>[
      _presence(state: 'done', agentType: 'codex', handle: '1'),
      _presence(state: 'working', agentType: 'opencode', handle: '2'),
      _presence(state: 'waiting', agentType: 'claude', handle: '3'),
      _presence(state: 'blocked', agentType: 'cursor', handle: '4'),
    ]);

    expect(
      groups.map((group) => group.kind).toList(),
      <WorkspaceAgentGroupKind>[
        WorkspaceAgentGroupKind.waiting,
        WorkspaceAgentGroupKind.blocked,
        WorkspaceAgentGroupKind.working,
        WorkspaceAgentGroupKind.done,
      ],
    );
  });

  test('interrupted wins over reported state', () {
    final groups = groupWorkspaceAgentRuns(<AgentPresenceSummary>[
      _presence(state: 'working', interrupted: true, handle: '1'),
      _presence(state: 'done', handle: '2'),
    ]);

    expect(groups.first.kind, WorkspaceAgentGroupKind.interrupted);
    expect(groups.first.runs, hasLength(1));
    expect(groups.last.kind, WorkspaceAgentGroupKind.done);
  });

  test('empty presence yields no groups', () {
    expect(groupWorkspaceAgentRuns(const <AgentPresenceSummary>[]), isEmpty);
  });

  test('one agent becomes the workspace primary and is not listed', () {
    final agent = _presence(state: 'working');
    final split = splitWorkspaceAgentPresence(<AgentPresenceSummary>[agent]);

    expect(split.primary, agent);
    expect(split.listed, isEmpty);
  });

  test('two or more agents stay listed without a workspace primary', () {
    final first = _presence(state: 'working', handle: '1');
    final second = _presence(state: 'done', handle: '2');
    final split = splitWorkspaceAgentPresence(<AgentPresenceSummary>[
      first,
      second,
    ]);

    expect(split.primary, isNull);
    expect(split.listed, <AgentPresenceSummary>[first, second]);
  });

  test(
    'a single main-panel agent stays on the row when others are secondary',
    () {
      final main = _presence(state: 'working', handle: '1');
      final side = _presence(state: 'done', handle: '2');
      final split = splitWorkspaceAgentPresence(
        <AgentPresenceSummary>[main, side],
        mainTabIds: <String>{'tab-1'},
      );

      expect(split.primary, main);
      expect(split.listed, <AgentPresenceSummary>[side]);
    },
  );

  test('two main-panel agents stay listed along with secondary runs', () {
    final first = _presence(state: 'working', handle: '1');
    final second = _presence(state: 'done', handle: '2');
    final side = _presence(state: 'waiting', handle: '3');
    final split = splitWorkspaceAgentPresence(
      <AgentPresenceSummary>[first, second, side],
      mainTabIds: <String>{'tab-1', 'tab-2'},
    );

    expect(split.primary, isNull);
    expect(split.listed, <AgentPresenceSummary>[first, second, side]);
  });

  test('no agents yields an empty split', () {
    final split = splitWorkspaceAgentPresence(const <AgentPresenceSummary>[]);

    expect(split.primary, isNull);
    expect(split.listed, isEmpty);
  });
}
