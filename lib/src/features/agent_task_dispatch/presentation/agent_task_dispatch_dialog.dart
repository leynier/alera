import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/design_system/layout/alera_section_header.dart';
import 'package:alera/src/design_system/surfaces/hover_container.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/presentation/agent_identity_icon.dart';
import 'package:alera/src/features/agent_task_dispatch/application/agent_task_dispatch_service.dart';
import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_status_projection.dart';
import 'package:alera/src/features/workbench/presentation/widgets/agent_run_state_indicator.dart';
import 'package:flutter/material.dart';

/// Presentational picker: running agents in the workspace, or a profile that
/// opens a new tab. Data and the selection callback come in via parameters.
class const AgentTaskDispatchDialog({
  super.key,
  required this.request,
  required this.catalog,
}) extends StatelessWidget {
  final AgentTaskDispatchRequest request;
  final AgentTaskDispatchCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = request.message?.trim();
    return AleraDialog(
      maxWidth: AleraTokens.dialogWidth,
      maxHeight: AleraTokens.dialogMaxHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AleraTokens.space16,
          AleraTokens.space12,
          AleraTokens.space16,
          AleraTokens.space16,
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            AleraDialogHeader(
              title: request.title,
              onClose: () => Navigator.of(context).pop(),
            ),
            if (message != null && message.isNotEmpty) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            ],
            const SizedBox(height: AleraTokens.space12),
            Flexible(child: _body(context, theme)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, ThemeData theme) {
    if (catalog.isEmpty) {
      return const AleraEmptyState(
        icon: AleraIcons.agent,
        title: 'No Agents Available',
        message: 'Add an agent profile in Settings, then send work here.',
      );
    }
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: <Widget>[
        const AleraSectionHeader(
          label: 'Running Agents',
          padding: EdgeInsets.only(
            left: AleraTokens.space4,
            right: AleraTokens.space4,
            bottom: AleraTokens.space4,
          ),
        ),
        if (catalog.runningAgents.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AleraTokens.space4,
              AleraTokens.space4,
              AleraTokens.space4,
              AleraTokens.space8,
            ),
            child: Text(
              'No running agents in this workspace.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          )
        else
          for (final run in catalog.runningAgents)
            _DispatchRow(
              title: agentTaskDispatchTabLabel(run.tab),
              subtitle: agentRunStateLabel(run.status),
              leading: _runningLeading(run),
              onTap: () => Navigator.of(
                context,
              ).pop(AgentTaskDispatchRunningAgentSelection(tabId: run.tab.id)),
            ),
        const SizedBox(height: AleraTokens.space8),
        const AleraSectionHeader(
          label: 'New Tab',
          padding: EdgeInsets.only(
            left: AleraTokens.space4,
            right: AleraTokens.space4,
            top: AleraTokens.space8,
            bottom: AleraTokens.space4,
          ),
        ),
        if (catalog.profiles.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AleraTokens.space4),
            child: Text(
              'No agent profiles to open.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          )
        else
          for (final profile in catalog.profiles)
            _DispatchRow(
              title: profile.name,
              subtitle: _profileSubtitle(profile),
              leading: _profileLeading(profile),
              onTap: () => Navigator.of(context)
                  .pop(AgentTaskDispatchNewTabSelection(profileId: profile.id)),
            ),
      ],
    );
  }

  Widget _runningLeading(WorkspaceAgentRun run) {
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        AgentRunStateIndicator(status: run.status, size: 12),
        const SizedBox(width: AleraTokens.space6),
        AgentIdentityIcon(agentType: run.status.agentType, size: 14),
      ],
    );
  }

  Widget _profileLeading(AgentProfile profile) {
    final agentType = AgentType.tryParse(profile.agentType);
    if (agentType == null) {
      return const Icon(
        AleraIcons.agent,
        size: 14,
        color: AleraTokens.foregroundMuted,
      );
    }
    return AgentIdentityIcon(agentType: agentType, size: 14);
  }

  String? _profileSubtitle(AgentProfile profile) {
    final description = profile.description.trim();
    if (description.isNotEmpty) {
      return description;
    }
    if (profile.id == catalog.defaultProfileId) {
      return 'Default profile';
    }
    final agentType = AgentType.tryParse(profile.agentType);
    return agentType == null ? null : agentDisplayName(agentType);
  }
}

class const _DispatchRow({
  required this.title,
  required this.onTap,
  this.subtitle,
  this.leading,
}) extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HoverContainer(
      onTap: onTap,
      borderRadius: AleraTokens.radiusSm,
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space8,
        vertical: AleraTokens.space8,
      ),
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading!,
            const SizedBox(width: AleraTokens.space8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foreground,
                  ),
                ),
                if (subtitle case final subtitle? when subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
