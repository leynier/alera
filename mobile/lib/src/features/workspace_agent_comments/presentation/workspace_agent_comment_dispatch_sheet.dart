import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/runtime/domain/agent_profile_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/domain/workspace_agent_comment_target.dart';
import 'package:flutter/material.dart';

/// Lets the user pick a running agent or an Agent Profile for queued comments.
/// Pops with the chosen target, or `null` when dismissed.
Future<WorkspaceAgentCommentTarget?> showWorkspaceAgentCommentDispatchSheet(
  BuildContext context, {
  required List<AgentPresenceSummary> runningAgents,
  required List<AgentProfileSummary> profiles,
}) {
  return showModalBottomSheet<WorkspaceAgentCommentTarget>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => WorkspaceAgentCommentDispatchSheet(
      runningAgents: runningAgents,
      profiles: profiles,
    ),
  );
}

class const WorkspaceAgentCommentDispatchSheet({
  super.key,
  required final List<AgentPresenceSummary> runningAgents,
  required final List<AgentProfileSummary> profiles,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              child: Text(
                'Send Comments to Agent',
                style: theme.textTheme.titleMedium,
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
                  leading: const Icon(AleraIcons.terminal, size: 20),
                  title: Text(_agentLabel(agent)),
                  subtitle: Text(agent.state),
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
                  leading: const Icon(AleraIcons.add, size: 20),
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
  return title.isEmpty ? agent.agentType : title;
}
