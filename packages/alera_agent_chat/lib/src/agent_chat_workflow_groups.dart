import 'package:alera_agent_chat/src/agent_chat_goal.dart';
import 'package:alera_agent_chat/src/agent_chat_subagent.dart';
import 'package:alera_agent_chat/src/agent_chat_worked_actions.dart';
import 'package:alera_agent_chat/src/agent_chat_workflow.dart';

/// Where a member is once its workflow is taken into account: a member the
/// provider still lists as queued or running is settled with the workflow.
enum AgentChatWorkflowMemberStatus {
  queued,
  running,
  completed,
  failed,
  stopped;

  bool get active => this == queued || this == running;

  String get label => switch (this) {
    queued => 'Queued',
    running => 'Running',
    completed => 'Completed',
    failed => 'Failed',
    stopped => 'Stopped',
  };
}

/// One member of a workflow, as the workflow's views show it.
final class AgentChatWorkflowMember {
  AgentChatWorkflowMember(this.agent, AgentChatSubagentStatus workflow)
    : status = switch (agent.state) {
        _
            when workflow.settled &&
                (agent.state == AgentChatWorkflowAgentState.queued ||
                    agent.state == AgentChatWorkflowAgentState.running) =>
          switch (workflow) {
            AgentChatSubagentStatus.failed =>
              AgentChatWorkflowMemberStatus.failed,
            AgentChatSubagentStatus.completed =>
              AgentChatWorkflowMemberStatus.completed,
            _ => AgentChatWorkflowMemberStatus.stopped,
          },
        AgentChatWorkflowAgentState.queued =>
          AgentChatWorkflowMemberStatus.queued,
        AgentChatWorkflowAgentState.running =>
          AgentChatWorkflowMemberStatus.running,
        AgentChatWorkflowAgentState.completed =>
          AgentChatWorkflowMemberStatus.completed,
        AgentChatWorkflowAgentState.failed =>
          AgentChatWorkflowMemberStatus.failed,
      };

  final AgentChatWorkflowAgent agent;
  final AgentChatWorkflowMemberStatus status;

  int get index => agent.index;

  /// The provider reports a settled member's duration, not its end.
  DateTime? get completedAt {
    final start = agent.startedAt;
    final duration = agent.durationMs;
    if (status.active || start == null || duration == null) return null;
    return start.add(Duration(milliseconds: duration));
  }

  /// "Working 12s", "Completed in 1m 5s", else the status.
  String statusLabel(DateTime now) {
    final start = agent.startedAt;
    if (status == AgentChatWorkflowMemberStatus.running && start != null) {
      return 'Working ${agentChatDurationLabel(_since(start, now))}';
    }
    final end = completedAt;
    if (status == AgentChatWorkflowMemberStatus.completed &&
        start != null &&
        end != null) {
      return 'Completed in ${agentChatDurationLabel(end.difference(start))}';
    }
    return status.label;
  }
}

Duration _since(DateTime start, DateTime now) {
  final elapsed = now.difference(start);
  return elapsed.isNegative ? Duration.zero : elapsed;
}

enum AgentChatWorkflowPhaseState { pending, running, done }

/// A phase of the plan with its members, oldest spawn first.
final class const AgentChatWorkflowPhaseGroup({
  required final int index,
  required final String title,
  required final List<AgentChatWorkflowMember> members,
  required final AgentChatWorkflowPhaseState state,
  required final int settledCount,
}) {
  /// "running", "failed", "stopped", "done" or "not started".
  String get statusLabel {
    if (state == AgentChatWorkflowPhaseState.running) return 'running';
    if (members.any((m) => m.status == AgentChatWorkflowMemberStatus.failed)) {
      return 'failed';
    }
    if (members.any((m) => m.status == AgentChatWorkflowMemberStatus.stopped)) {
      return 'stopped';
    }
    return state == AgentChatWorkflowPhaseState.done ? 'done' : 'not started';
  }

  /// The phase's wall clock: its members run in parallel, so from the first
  /// start to the last finish, still open while the phase runs.
  Duration? elapsed(DateTime now) {
    final starts = <DateTime>[
      for (final member in members) ?member.agent.startedAt,
    ]..sort();
    if (starts.isEmpty) return null;
    if (state == AgentChatWorkflowPhaseState.running) {
      return _since(starts.first, now);
    }
    final ends = <DateTime>[for (final member in members) ?member.completedAt]
      ..sort();
    return ends.isEmpty ? null : _since(starts.first, ends.last);
  }

  /// "2/3 agents".
  String get countLabel =>
      '$settledCount/${members.length} '
      '${members.length == 1 ? 'agent' : 'agents'}';
}

/// A workflow with its members grouped by phase, as T3 Code's lineage row
/// draws it. The declared plan lags the members, as the provider only
/// admits a phase once something in it starts, so members name phases too
/// and the declared titles win.
final class AgentChatWorkflowGroup {
  AgentChatWorkflowGroup._(
    this.workflow,
    this.status,
    this.phases,
    this.unphased,
  );

  factory AgentChatWorkflowGroup.build(
    AgentChatWorkflow workflow,
    AgentChatSubagentStatus status,
  ) {
    final members = <AgentChatWorkflowMember>[
      for (final agent in workflow.agents)
        AgentChatWorkflowMember(agent, status),
    ]..sort((left, right) => left.index.compareTo(right.index));
    final titles = <int, String>{};
    for (final member in members) {
      final phase = member.agent.phaseIndex;
      if (phase == null) continue;
      titles[phase] =
          member.agent.phaseTitle ?? titles[phase] ?? 'Phase ${phase + 1}';
    }
    for (final phase in workflow.phases) {
      titles[phase.index] = phase.title;
    }
    final indexes = titles.keys.toList()..sort();
    return AgentChatWorkflowGroup._(
      workflow,
      status,
      <AgentChatWorkflowPhaseGroup>[
        for (final index in indexes)
          _phase(index, titles[index]!, <AgentChatWorkflowMember>[
            for (final member in members)
              if (member.agent.phaseIndex == index) member,
          ]),
      ],
      <AgentChatWorkflowMember>[
        for (final member in members)
          if (member.agent.phaseIndex == null) member,
      ],
    );
  }

  final AgentChatWorkflow workflow;

  /// The workflow's own status, as its sub-agent record reports it.
  final AgentChatSubagentStatus status;
  final List<AgentChatWorkflowPhaseGroup> phases;

  /// Members with no phase; they show under the workflow itself.
  final List<AgentChatWorkflowMember> unphased;

  Iterable<AgentChatWorkflowMember> get members => <AgentChatWorkflowMember>[
    for (final phase in phases) ...phase.members,
    ...unphased,
  ];

  /// "Ran 3 sub-agents", or "Kicked off 3 sub-agents" while it runs.
  String get lead {
    final count = workflow.agents.length;
    final verb = status.settled ? 'Ran' : 'Kicked off';
    return count == 0
        ? '$verb sub-agents'
        : '$verb $count ${count == 1 ? 'sub-agent' : 'sub-agents'}';
  }

  /// "2 working", "Workflow failed", "1 failed", "Completed": T3 Code's
  /// spawn summary. A workflow keeps running between member launches, so its
  /// own status decides whether it is live.
  String get summary {
    final all = members.toList();
    final working = all.where((member) => member.status.active).length;
    if (!status.settled) return working > 0 ? '$working working' : 'Working';
    if (status == AgentChatSubagentStatus.failed) return 'Workflow failed';
    if (status == AgentChatSubagentStatus.stopped) return 'Workflow stopped';
    final failed = all
        .where(
          (member) => member.status == AgentChatWorkflowMemberStatus.failed,
        )
        .length;
    if (failed > 0) return '$failed failed';
    return all.isEmpty ? 'Status unavailable' : 'Completed';
  }

  /// "71k tokens · 12 tool calls · 1m 5s", or `null` before any usage.
  String? get usage => agentChatWorkflowUsageLabel(
    totalTokens: workflow.totalTokens,
    toolCalls: workflow.toolCalls,
    durationMs: workflow.durationMs,
  );
}

String? agentChatWorkflowUsageLabel({
  int? totalTokens,
  int? toolCalls,
  int? durationMs,
}) {
  final parts = <String>[
    if (totalTokens != null) '${agentChatGoalTokenLabel(totalTokens)} tokens',
    if (toolCalls != null)
      '$toolCalls ${toolCalls == 1 ? 'tool call' : 'tool calls'}',
    if (durationMs != null)
      agentChatDurationLabel(Duration(milliseconds: durationMs)),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

AgentChatWorkflowPhaseGroup _phase(
  int index,
  String title,
  List<AgentChatWorkflowMember> members,
) {
  final settled = members.where((member) => !member.status.active).length;
  return AgentChatWorkflowPhaseGroup(
    index: index,
    title: title,
    members: members,
    state: members.isEmpty
        ? AgentChatWorkflowPhaseState.pending
        : members.any((member) => member.status.active)
        ? AgentChatWorkflowPhaseState.running
        : AgentChatWorkflowPhaseState.done,
    settledCount: settled,
  );
}
