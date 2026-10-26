import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// The color a member's status draws in.
Color agentChatWorkflowMemberColor(AgentChatWorkflowMemberStatus status) =>
    switch (status) {
      AgentChatWorkflowMemberStatus.failed => AleraTokens.error,
      AgentChatWorkflowMemberStatus.running => AleraTokens.foreground,
      AgentChatWorkflowMemberStatus.completed => AleraTokens.foregroundMuted,
      AgentChatWorkflowMemberStatus.queued ||
      AgentChatWorkflowMemberStatus.stopped => AleraTokens.foregroundFaint,
    };

/// A workflow's phases, each folding its members, as T3 Code's lineage
/// workflow row lists them. The running phase opens itself until the person
/// picks a side for it; members without a phase follow the phases.
class const AgentChatWorkflowPhases({
  super.key,
  required final AgentChatWorkflowGroup group,
  final ValueChanged<AgentChatWorkflowMember>? onOpenMember,
}) extends StatefulWidget {
  @override
  State<AgentChatWorkflowPhases> createState() =>
      _AgentChatWorkflowPhasesState();
}

class _AgentChatWorkflowPhasesState extends State<AgentChatWorkflowPhases> {
  final Map<int, bool> _open = <int, bool>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now().toUtc();
    final phases = widget.group.phases
        .where((phase) => phase.members.isNotEmpty)
        .toList();
    final unphased = widget.group.unphased;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final phase in phases) ...<Widget>[
          _PhaseHeader(
            phase: phase,
            open: _open[phase.index] ?? phase.state == .running,
            now: now,
            onToggle: () => setState(
              () => _open[phase.index] =
                  !(_open[phase.index] ?? phase.state == .running),
            ),
          ),
          if (_open[phase.index] ?? phase.state == .running)
            for (final member in phase.members)
              _MemberRow(
                member: member,
                now: now,
                indent: true,
                onOpen: widget.onOpenMember,
              ),
        ],
        for (final member in unphased)
          _MemberRow(
            member: member,
            now: now,
            indent: false,
            onOpen: widget.onOpenMember,
          ),
        if (phases.isEmpty && unphased.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AleraTokens.space6),
            child: Text(
              'No agents yet',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AleraTokens.foregroundFaint,
              ),
            ),
          ),
      ],
    );
  }
}

class const _PhaseHeader({
  required final AgentChatWorkflowPhaseGroup phase,
  required final bool open,
  required final DateTime now,
  required final VoidCallback onToggle,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = phase.statusLabel;
    final running = phase.state == AgentChatWorkflowPhaseState.running;
    final elapsed = phase.elapsed(now);
    final faint = theme.textTheme.labelSmall?.copyWith(
      color: AleraTokens.foregroundFaint,
    );
    return Semantics(
      button: true,
      expanded: open,
      label: '${phase.title} phase, $status',
      child: InkWell(
        key: ValueKey<String>('agent-chat-workflow-phase-${phase.index}'),
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space6),
          child: Row(
            children: <Widget>[
              Icon(
                open ? AleraIcons.chevronDown : AleraIcons.chevronRight,
                size: AleraTokens.iconMd,
                color: AleraTokens.foregroundFaint,
              ),
              const SizedBox(width: AleraTokens.space6),
              Expanded(
                child: Text(
                  phase.title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: running
                        ? AleraTokens.foreground
                        : AleraTokens.foregroundMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (status == 'failed') ...<Widget>[
                Text(
                  'Failed',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AleraTokens.error,
                  ),
                ),
                const SizedBox(width: AleraTokens.space6),
              ],
              Text(phase.countLabel, style: faint),
              if (elapsed != null) ...<Widget>[
                const SizedBox(width: AleraTokens.space6),
                Text(agentChatDurationLabel(elapsed), style: faint),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class const _MemberRow({
  required final AgentChatWorkflowMember member,
  required final DateTime now,
  required final bool indent,
  final ValueChanged<AgentChatWorkflowMember>? onOpen,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = agentChatWorkflowMemberColor(member.status);
    final open = onOpen;
    return Tooltip(
      message: 'Open ${member.agent.label}',
      child: InkWell(
        key: ValueKey<String>('agent-chat-workflow-member-${member.index}'),
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        onTap: open == null ? null : () => open(member),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            indent ? AleraTokens.space24 : AleraTokens.space6,
            AleraTokens.space4,
            AleraTokens.space6,
            AleraTokens.space4,
          ),
          child: Row(
            children: <Widget>[
              Icon(AleraIcons.agent, size: AleraTokens.iconSm, color: color),
              const SizedBox(width: AleraTokens.space6),
              Expanded(
                child: Text(
                  member.agent.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: member.status.active
                        ? AleraTokens.foreground
                        : AleraTokens.foregroundMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AleraTokens.space6),
              Text(
                member.statusLabel(now),
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
