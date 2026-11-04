import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_subagent_actions.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_workflow_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The color a member's status draws in.
Color agentChatWorkflowMemberColor(AgentChatWorkflowMemberStatus status) =>
    switch (status) {
      AgentChatWorkflowMemberStatus.failed => AleraTokens.error,
      AgentChatWorkflowMemberStatus.running => AleraTokens.foreground,
      AgentChatWorkflowMemberStatus.completed => AleraTokens.foregroundMuted,
      AgentChatWorkflowMemberStatus.queued ||
      AgentChatWorkflowMemberStatus.stopped => AleraTokens.foregroundFaint,
    };

/// A workflow's phases, each folding its members. The running phase opens
/// itself until the person picks a side for it; a member opens its sheet
/// when the chat is in scope.
class const AgentChatWorkflowPhaseList({
  super.key,
  required final String callId,
  required final AgentChatWorkflowGroup group,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgentChatWorkflowPhaseList> createState() =>
      _AgentChatWorkflowPhaseListState();
}

class _AgentChatWorkflowPhaseListState
    extends ConsumerState<AgentChatWorkflowPhaseList> {
  final Map<int, bool> _open = <int, bool>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now().toUtc();
    final scope = AgentChatScope.maybeOf(context);
    final readable =
        scope != null &&
        (ref
                .watch(
                  agentChatCapabilityProvider(
                    scope.hostId,
                    AgentChatWire.workflowsCapability,
                  ),
                )
                .value ??
            false);
    ValueChanged<AgentChatWorkflowMember>? onOpen;
    if (scope != null) {
      final chat = AgentChatSubagentChat(
        hostId: scope.hostId,
        workspaceId: scope.workspaceId,
        chatId: scope.chatId,
      );
      onOpen = (member) => unawaited(
        showAgentChatWorkflowMemberSheet(
          context,
          chat: chat,
          callId: widget.callId,
          member: member,
          readable: readable,
        ),
      );
    }
    final phases = widget.group.phases
        .where((phase) => phase.members.isNotEmpty)
        .toList();
    final unphased = widget.group.unphased;
    bool open(AgentChatWorkflowPhaseGroup phase) =>
        _open[phase.index] ??
        phase.state == AgentChatWorkflowPhaseState.running;
    final faint = theme.textTheme.labelSmall?.copyWith(
      color: AleraTokens.foregroundFaint,
    );
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        for (final phase in phases) ...<Widget>[
          Semantics(
            button: true,
            expanded: open(phase),
            label: '${phase.title} phase, ${phase.statusLabel}',
            child: InkWell(
              key: ValueKey<String>('agent-chat-workflow-phase-${phase.index}'),
              onTap: () => setState(() => _open[phase.index] = !open(phase)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AleraTokens.minTapTarget,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      open(phase)
                          ? AleraIcons.chevronDown
                          : AleraIcons.chevronRight,
                      size: AleraTokens.space16,
                      color: AleraTokens.foregroundFaint,
                    ),
                    const SizedBox(width: AleraTokens.space6),
                    Expanded(
                      child: Text(
                        phase.title,
                        style: theme.textTheme.bodySmall,
                        overflow: .ellipsis,
                      ),
                    ),
                    if (phase.statusLabel == 'failed')
                      Padding(
                        padding: const EdgeInsets.only(
                          right: AleraTokens.space6,
                        ),
                        child: Text(
                          'Failed',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AleraTokens.error,
                          ),
                        ),
                      ),
                    Text(phase.countLabel, style: faint),
                    if (phase.elapsed(now) case final elapsed?) ...<Widget>[
                      const SizedBox(width: AleraTokens.space6),
                      Text(agentChatDurationLabel(elapsed), style: faint),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (open(phase))
            for (final member in phase.members)
              _MemberTile(
                member: member,
                now: now,
                indent: true,
                onOpen: onOpen,
              ),
        ],
        for (final member in unphased)
          _MemberTile(member: member, now: now, indent: false, onOpen: onOpen),
        if (phases.isEmpty && unphased.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AleraTokens.space6),
            child: Text('No agents yet', style: faint),
          ),
      ],
    );
  }
}

class const _MemberTile({
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
    return InkWell(
      key: ValueKey<String>('agent-chat-workflow-member-${member.index}'),
      onTap: open == null ? null : () => open(member),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AleraTokens.minTapTarget),
        child: Padding(
          padding: EdgeInsets.only(
            left: indent ? AleraTokens.space24 : AleraTokens.space6,
          ),
          child: Row(
            children: <Widget>[
              Icon(AleraIcons.agent, size: AleraTokens.space16, color: color),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text(
                  member.agent.label,
                  style: theme.textTheme.bodySmall,
                  overflow: .ellipsis,
                ),
              ),
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

/// A workflow on its own screen: how its run is going, its usage, its
/// script and its phases.
class const AgentChatWorkflowSection({
  super.key,
  required final AgentChatSubagentChat chat,
  required final String callId,
  required final AgentChatWorkflowGroup group,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final readable =
        ref
            .watch(
              agentChatCapabilityProvider(
                chat.hostId,
                AgentChatWire.workflowsCapability,
              ),
            )
            .value ??
        false;
    final usage = group.usage;
    return Container(
      key: ValueKey<String>('agent-chat-workflow-section-$callId'),
      margin: const EdgeInsets.only(bottom: AleraTokens.space12),
      padding: const EdgeInsets.all(AleraTokens.space8),
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(AleraIcons.workflow, size: AleraTokens.space16),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text(
                  '${group.lead} · ${group.summary}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (readable && group.workflow.scriptPath != null)
                TextButton.icon(
                  key: const ValueKey<String>(
                    'agent-chat-workflow-view-script',
                  ),
                  onPressed: () => unawaited(
                    showAgentChatWorkflowScriptSheet(
                      context,
                      chat: chat,
                      callId: callId,
                    ),
                  ),
                  icon: const Icon(AleraIcons.code, size: AleraTokens.space16),
                  label: const Text('View Script'),
                ),
            ],
          ),
          if (usage != null)
            Text(
              usage,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AleraTokens.foregroundFaint,
              ),
            ),
          AgentChatWorkflowPhaseList(callId: callId, group: group),
        ],
      ),
    );
  }
}
