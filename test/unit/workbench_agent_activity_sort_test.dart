import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/workbench/application/workbench_agent_activity_sort.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _now = DateTime.utc(2026, 7, 4, 12);

WorkspaceTabRecord _tab(String id, String workspaceId) {
  return WorkspaceTabRecord(
    id: id,
    workspaceId: workspaceId,
    kind: WorkspaceTabKind.terminal,
    title: id,
    createdAt: _now,
    updatedAt: _now,
  );
}

AgentStatusEntry _status(
  WorkspaceTabRecord tab, {
  required AgentStatusState state,
  bool? interrupted,
  Duration age = Duration.zero,
}) {
  return AgentStatusEntry(
    terminalSessionId: tab.terminalSessionId,
    workspaceId: tab.workspaceId,
    tabId: tab.id,
    agentType: AgentType.claude,
    state: state,
    prompt: 'Prompt',
    updatedAt: _now.subtract(age),
    stateStartedAt: _now.subtract(age),
    interrupted: interrupted,
  );
}

void main() {
  group('workspaceAttention', () {
    test('waiting and blocked classify as needsYou', () {
      for (final state in <AgentStatusState>[
        AgentStatusState.waiting,
        AgentStatusState.blocked,
      ]) {
        final tab = _tab('t-1', 'w-1');
        final attention = workspaceAttention(
          tabs: <WorkspaceTabRecord>[tab],
          agentStatuses: <String, AgentStatusEntry>{
            tab.terminalSessionId: _status(tab, state: state),
          },
          now: _now,
        );
        expect(attention.attentionClass, AgentAttentionClass.needsYou);
      }
    });

    test('interrupted done classifies as needsYou', () {
      final tab = _tab('t-1', 'w-1');
      final attention = workspaceAttention(
        tabs: <WorkspaceTabRecord>[tab],
        agentStatuses: <String, AgentStatusEntry>{
          tab.terminalSessionId: _status(
            tab,
            state: AgentStatusState.done,
            interrupted: true,
          ),
        },
        now: _now,
      );
      expect(attention.attentionClass, AgentAttentionClass.needsYou);
    });

    test('stale statuses are ignored', () {
      final tab = _tab('t-1', 'w-1');
      final attention = workspaceAttention(
        tabs: <WorkspaceTabRecord>[tab],
        agentStatuses: <String, AgentStatusEntry>{
          tab.terminalSessionId: _status(
            tab,
            state: AgentStatusState.waiting,
            age: agentActivityStaleness + const Duration(minutes: 1),
          ),
        },
        now: _now,
      );
      expect(attention.attentionClass, AgentAttentionClass.idle);
    });

    test('the most urgent run wins', () {
      final working = _tab('t-1', 'w-1');
      final waiting = _tab('t-2', 'w-1');
      final attention = workspaceAttention(
        tabs: <WorkspaceTabRecord>[working, waiting],
        agentStatuses: <String, AgentStatusEntry>{
          working.terminalSessionId: _status(
            working,
            state: AgentStatusState.working,
          ),
          waiting.terminalSessionId: _status(
            waiting,
            state: AgentStatusState.waiting,
            age: const Duration(minutes: 5),
          ),
        },
        now: _now,
      );
      expect(attention.attentionClass, AgentAttentionClass.needsYou);
      expect(attention.attentionAt, _now.subtract(const Duration(minutes: 5)));
    });
  });

  group('compareByAgentActivity', () {
    test('lower class ranks first regardless of recency', () {
      final result = compareByAgentActivity(
        aActivity: AgentActivityRank(
          attentionClass: AgentAttentionClass.working,
          activityAt: _now,
        ),
        aName: 'a',
        bActivity: AgentActivityRank(
          attentionClass: AgentAttentionClass.needsYou,
          activityAt: _now.subtract(const Duration(days: 1)),
        ),
        bName: 'b',
      );
      expect(result, greaterThan(0));
    });

    test('same class ranks by recency then name', () {
      final result = compareByAgentActivity(
        aActivity: AgentActivityRank(
          attentionClass: AgentAttentionClass.done,
          activityAt: _now,
        ),
        aName: 'a',
        bActivity: AgentActivityRank(
          attentionClass: AgentAttentionClass.done,
          activityAt: _now.subtract(const Duration(minutes: 1)),
        ),
        bName: 'b',
      );
      expect(result, lessThan(0));
    });

    test(
      'terminal activity ranks before an alphabetically earlier inactive',
      () {
        final result = compareByAgentActivity(
          aActivity: AgentActivityRank(
            attentionClass: AgentAttentionClass.idle,
            activityAt: _now,
          ),
          aName: 'zebra',
          bActivity: null,
          bName: 'alpha',
        );
        expect(result, lessThan(0));
      },
    );

    test('inactive entries sort alphabetically', () {
      final result = compareByAgentActivity(
        aActivity: null,
        aName: 'zebra',
        bActivity: null,
        bName: 'alpha',
      );
      expect(result, greaterThan(0));
    });
  });

  group('aggregateAgentActivityBySubtree', () {
    test('promotes an ancestor using its best descendant activity', () {
      final working = AgentActivityRank(
        attentionClass: AgentAttentionClass.working,
        activityAt: _now,
      );
      final waiting = AgentActivityRank(
        attentionClass: AgentAttentionClass.needsYou,
        activityAt: _now.subtract(const Duration(minutes: 5)),
      );
      final ranks = aggregateAgentActivityBySubtree(
        workspaces: <({String id, String? parentId})>[
          (id: 'root', parentId: null),
          (id: 'child', parentId: 'root'),
          (id: 'grandchild', parentId: 'child'),
        ],
        directActivityByWorkspaceId: <String, AgentActivityRank?>{
          'child': working,
          'grandchild': waiting,
        },
      );

      expect(ranks['root'], same(waiting));
      expect(ranks['child'], same(waiting));
      expect(ranks['grandchild'], same(waiting));
    });

    test('terminates when parent relationships contain a cycle', () {
      final activity = AgentActivityRank(
        attentionClass: AgentAttentionClass.working,
        activityAt: _now,
      );
      final ranks = aggregateAgentActivityBySubtree(
        workspaces: <({String id, String? parentId})>[
          (id: 'a', parentId: 'b'),
          (id: 'b', parentId: 'a'),
        ],
        directActivityByWorkspaceId: <String, AgentActivityRank?>{
          'b': activity,
        },
      );

      expect(ranks['a'], same(activity));
      expect(ranks['b'], same(activity));
    });
  });
}
