import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_identity_icon.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_run_state_indicator.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment_target.dart';
import 'package:flutter/material.dart';

/// Lets the user pick a running agent or an Agent Profile.
///
/// File comments, Restack, Fix Failed Checks, and Watch and Fix share this
/// sheet. Each row shows that agent's brand icon, matching the desktop
/// dispatch dialog. Pops with the chosen target, or `null` when dismissed.
Future<WorkspaceAgentCommentTarget?> showWorkspaceAgentCommentDispatchSheet(
  BuildContext context, {
  required List<AgentPresenceSummary> runningAgents,
  required List<AgentProfileSummary> profiles,
  String title = 'Send Comments to Agent',
  String? message,
}) {
  return showModalBottomSheet<WorkspaceAgentCommentTarget>(
    context: context,
    isScrollControlled: true,
    builder: (context) => WorkspaceAgentCommentDispatchSheet(
      runningAgents: runningAgents,
      profiles: profiles,
      title: title,
      message: message,
    ),
  );
}

class const WorkspaceAgentCommentDispatchSheet({
  super.key,
  required final List<AgentPresenceSummary> runningAgents,
  required final List<AgentProfileSummary> profiles,
  this.title = 'Send Comments to Agent',
  this.message,
}) extends StatelessWidget {
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final description = message?.trim();
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: ListView(
          shrinkWrap: true,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space16,
              ),
              child: Text(title, style: theme.textTheme.titleMedium),
            ),
            if (description != null && description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AleraTokens.space16,
                  AleraTokens.space8,
                  AleraTokens.space16,
                  0,
                ),
                child: Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ),
            if (runningAgents.isEmpty && profiles.isEmpty)
              const Padding(
                padding: AleraTokens.contentPadding,
                child: Text(
                  'Start an agent or add an Agent Profile on this host to send comments.',
                ),
              ),
            if (runningAgents.isNotEmpty) ...<Widget>[
              const AleraSectionHeader(label: 'Running Agents'),
              for (final agent in runningAgents)
                ListTile(
                  minTileHeight: AleraTokens.minTapTarget,
                  leading: _RunningAgentLeading(agent: agent),
                  title: Text(_agentLabel(agent)),
                  subtitle: Text(agentRunStateLabel(agent)),
                  onTap: () =>
                      Navigator.of(context)
                          .pop(RunningAgentCommentTarget(agent)),
                ),
            ],
            if (profiles.isNotEmpty) ...<Widget>[
              const AleraSectionHeader(label: 'New Tab From Profile'),
              for (final profile in profiles)
                ListTile(
                  minTileHeight: AleraTokens.minTapTarget,
                  leading: AgentIdentityIcon(
                    agentType: profile.agentType,
                    size: AleraTokens.iconMd,
                    showTooltip: false,
                  ),
                  title: Text(profile.name),
                  onTap: () =>
                      Navigator.of(context)
                          .pop(AgentProfileCommentTarget(profile)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

String _agentLabel(AgentPresenceSummary agent) {
  final title = agent.title.trim();
  return title.isEmpty ? agentDisplayName(agent.agentType) : title;
}

/// Status glyph plus the agent brand mark, same pairing as the desktop
/// dispatch row and the workspace agent rows.
class const _RunningAgentLeading({required final AgentPresenceSummary agent})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        AgentRunStateIndicator(status: agent, size: AleraTokens.iconSm),
        const SizedBox(width: AleraTokens.space6),
        AgentIdentityIcon(
          agentType: agent.agentType,
          size: AleraTokens.iconMd,
          showTooltip: false,
        ),
      ],
    );
  }
}
