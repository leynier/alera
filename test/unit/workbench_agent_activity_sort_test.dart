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
        aAttention: const WorkspaceAttention(
          attentionClass: AgentAttentionClass.working,
        ),
        aFallback: _now,
        aName: 'a',
        bAttention: const WorkspaceAttention(
          attentionClass: AgentAttentionClass.needsYou,
        ),
        bFallback: _now.subtract(const Duration(days: 1)),
        bName: 'b',
      );
      expect(result, greaterThan(0));
    });

    test('same class ranks by recency then name', () {
      final result = compareByAgentActivity(
        aAttention: WorkspaceAttention(
          attentionClass: AgentAttentionClass.done,
          attentionAt: _now,
        ),
        aFallback: _now,
        aName: 'a',
        bAttention: WorkspaceAttention(
          attentionClass: AgentAttentionClass.done,
          attentionAt: _now.subtract(const Duration(minutes: 1)),
        ),
        bFallback: _now,
        bName: 'b',
      );
      expect(result, lessThan(0));
    });

    test('idle entries fall back to the provided timestamp', () {
      final result = compareByAgentActivity(
        aAttention: WorkspaceAttention.idle,
        aFallback: _now.subtract(const Duration(days: 2)),
        aName: 'a',
        bAttention: WorkspaceAttention.idle,
        bFallback: _now,
        bName: 'b',
      );
      expect(result, greaterThan(0));
    });
  });

  group('stabilizeActiveEntry', () {
    test('re-inserts the active id at its previous index', () {
      final stabilized = stabilizeActiveEntry<String>(
        sorted: <String>['b', 'c', 'a'],
        idOf: (id) => id,
        previousOrder: <String>['a', 'b', 'c'],
        activeId: 'a',
      );
      expect(stabilized, <String>['a', 'b', 'c']);
    });

    test('leaves the order untouched without an active id', () {
      final stabilized = stabilizeActiveEntry<String>(
        sorted: <String>['b', 'a'],
        idOf: (id) => id,
        previousOrder: <String>['a', 'b'],
        activeId: null,
      );
      expect(stabilized, <String>['b', 'a']);
    });

    test('ignores an active id missing from the previous order', () {
      final stabilized = stabilizeActiveEntry<String>(
        sorted: <String>['b', 'a'],
        idOf: (id) => id,
        previousOrder: const <String>[],
        activeId: 'a',
      );
      expect(stabilized, <String>['b', 'a']);
    });
  });
}
