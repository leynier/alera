import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/icons/alera_linked_worktree_icon.dart';
import 'package:alera_mobile/src/features/linked_issues/domain/mobile_linked_issue.dart';
import 'package:alera_mobile/src/features/linked_issues/presentation/mobile_linked_issue_icon.dart';
import 'package:alera_mobile/src/features/pull_requests/domain/mobile_pull_request_watch.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_pull_request_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_workspace_rows.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_agent_run_groups.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_identity_icon.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_run_state_indicator.dart';
import 'package:alera_mobile/src/features/workbench/presentation/mobile_agent_run_labels.dart';
import 'package:alera_mobile/src/features/workbench/presentation/mobile_workspace_agent_compact_summary.dart';
import 'package:alera_mobile/src/features/workbench/presentation/mobile_workspace_pull_request_status_icon.dart';
import 'package:flutter/material.dart';

part 'workspace_row_trays.dart';

/// Dense single-line workspace row mirroring the desktop sidebar anatomy.
class const MobileWorkspaceListRow({
  super.key,
  required final MobileWorkspaceEntryRow row,
  required final VoidCallback onTap,
  required final VoidCallback onLongPress,
  required final VoidCallback onMore,
  required final VoidCallback onToggleChildren,
  required final int terminalTabCount,
  required final bool agentsExpanded,
  required final VoidCallback onToggleAgents,
  required final ValueChanged<AgentPresenceSummary> onAgentTap,
  required final ValueChanged<AgentPresenceSummary> onCloseAgent,
  final List<AgentPresenceSummary> agentPresence =
      const <AgentPresenceSummary>[],
  final Set<String> mainTabIds = const <String>{},
  final bool showProjectIcon = false,
  final String? projectName,
  final MobileLinkedIssue? linkedIssue,
  final MobileWorkspacePullRequestSummary? pullRequestSummary,
  final MobilePullRequestWatch? pullRequestWatch,
}) extends StatelessWidget {
  /// Fixed leading slot so status glyphs do not shift the title (desktop: 14).
  static const double _statusSlotSize = 14;
  static const double _trayIconSize = 12;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = row.entry;
    final workspace = entry.workspace;
    final tags = _tagLabels(workspace);
    final depthPad = entry.depth * AleraTokens.space12;
    final rowLeft = AleraTokens.space12 + depthPad;
    final canToggleChildren = entry.hasVisibleChildren;
    final hasAgents = agentPresence.isNotEmpty;
    final split = splitWorkspaceAgentPresence(
      agentPresence,
      mainTabIds: mainTabIds,
    );
    final listedAgents = split.listed;
    final hasListedAgents = listedAgents.isNotEmpty;
    final pullRequestSummary =
        this.pullRequestSummary ??
        _pullRequestSummaryFallback(workspace.id, pullRequestWatch);
    final metadataIcons = <Widget>[
      if (showProjectIcon &&
          (projectName?.trim().isNotEmpty ?? false)) ...<Widget>[
        const SizedBox(width: AleraTokens.space6),
        Tooltip(
          message: projectName!,
          child: const Icon(
            AleraIcons.folderSpecial,
            size: _trayIconSize,
            color: AleraTokens.foregroundMuted,
          ),
        ),
      ],
      if (workspace.isMain) ...<Widget>[
        const SizedBox(width: AleraTokens.space6),
        const Tooltip(
          message: 'Project folder',
          child: Icon(
            AleraIcons.workspaceMain,
            size: _trayIconSize,
            color: AleraTokens.foregroundMuted,
          ),
        ),
      ] else ...<Widget>[
        const SizedBox(width: AleraTokens.space6),
        const Tooltip(
          message: 'Linked worktree',
          child: AleraLinkedWorktreeIcon(size: _trayIconSize),
        ),
      ],
      if (workspace.isPinned && !row.isPinnedCopy) ...<Widget>[
        const SizedBox(width: AleraTokens.space6),
        const Tooltip(
          message: 'Pinned workspace',
          child: Icon(
            AleraIcons.pin,
            size: _trayIconSize,
            color: AleraTokens.foregroundMuted,
          ),
        ),
      ],
      if (workspace.isArchived) ...<Widget>[
        const SizedBox(width: AleraTokens.space6),
        const Tooltip(
          message: 'Archived workspace',
          child: Icon(
            AleraIcons.archive,
            size: _trayIconSize,
            color: AleraTokens.foregroundMuted,
          ),
        ),
      ],
      if (pullRequestSummary case final summary?) ...<Widget>[
        const SizedBox(width: AleraTokens.space6),
        MobileWorkspacePullRequestStatusIcon(
          key: const Key('workspace-tray-pull-request'),
          summary: summary,
          size: _trayIconSize,
        ),
      ],
      if (pullRequestWatch case final watch?) ...<Widget>[
        const SizedBox(width: AleraTokens.space6),
        Tooltip(
          message: watch.tooltip,
          child: Icon(
            AleraIcons.visible,
            size: _trayIconSize,
            color: AleraTokens.foregroundMuted,
            key: const Key('workspace-tray-pr-watch'),
          ),
        ),
      ],
      if (linkedIssue case final issue?) ...<Widget>[
        const SizedBox(width: AleraTokens.space6),
        MobileLinkedIssueIcon(issue: issue, size: _trayIconSize),
      ],
      if (tags.isNotEmpty) ...<Widget>[
        const SizedBox(width: AleraTokens.space6),
        Tooltip(
          message: tags.join(', '),
          child: Row(
            mainAxisSize: .min,
            children: <Widget>[
              const Icon(
                AleraIcons.tag,
                size: _trayIconSize,
                color: AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space2),
              Text(
                '${tags.length}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                  fontWeight: .w600,
                ),
              ),
            ],
          ),
        ),
      ],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
      child: Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        children: <Widget>[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: .stretch,
              children: <Widget>[
                Expanded(
                  child: InkWell(
                    onTap: onTap,
                    onLongPress: onLongPress,
                    borderRadius: .circular(AleraTokens.radiusSm),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: AleraTokens.minTapTarget,
                      ),
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          rowLeft,
                          AleraTokens.space8,
                          AleraTokens.space4,
                          AleraTokens.space8,
                        ),
                        child: Row(
                          children: <Widget>[
                            SizedBox.square(
                              dimension: _statusSlotSize,
                              child: Center(
                                child: _WorkspaceStatusIndicator(
                                  hasAgents: hasAgents,
                                  state: hasAgents
                                      ? _mostUrgentState(agentPresence)
                                      : null,
                                  interrupted: hasAgents
                                      ? agentPresence
                                            .firstWhere(
                                              (status) =>
                                                  status.state ==
                                                  _mostUrgentState(
                                                    agentPresence,
                                                  ),
                                              orElse: () => agentPresence.first,
                                            )
                                            .interrupted
                                      : null,
                                  active: terminalTabCount > 0,
                                ),
                              ),
                            ),
                            const SizedBox(width: AleraTokens.space8),
                            if (split.primary
                                case final AgentPresenceSummary
                                    primary) ...<Widget>[
                              Tooltip(
                                message: mobileAgentRunDescription(primary),
                                child: AgentIdentityIcon(
                                  key: const Key('workspace-primary-agent'),
                                  agentType: primary.agentType,
                                  size: AleraTokens.space16,
                                  color: AleraTokens.foregroundMuted,
                                ),
                              ),
                              const SizedBox(width: AleraTokens.space6),
                            ],
                            Expanded(
                              child: Row(
                                children: <Widget>[
                                  Flexible(
                                    child: Row(
                                      mainAxisSize: .min,
                                      children: <Widget>[
                                        Flexible(
                                          child: Text(
                                            workspace.name,
                                            maxLines: 1,
                                            softWrap: false,
                                            overflow: .ellipsis,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  color: AleraTokens.foreground,
                                                  fontWeight: .w600,
                                                ),
                                          ),
                                        ),
                                        ...metadataIcons,
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (hasListedAgents || canToggleChildren)
                  _WorkspaceActionTray(
                    childCount: entry.visibleChildCount,
                    childrenCollapsed: entry.childrenCollapsed,
                    onToggleChildren: canToggleChildren
                        ? onToggleChildren
                        : null,
                    statuses: listedAgents,
                    agentsExpanded: agentsExpanded,
                    onToggleAgents: hasListedAgents ? onToggleAgents : null,
                  ),
                Align(
                  alignment: Alignment.center,
                  child: AleraIconButton(
                    tooltip: 'Workspace Actions',
                    onPressed: onMore,
                    icon: AleraIcons.more,
                    iconSize: 16,
                  ),
                ),
              ],
            ),
          ),
          if (hasListedAgents && agentsExpanded) ...<Widget>[
            const SizedBox(height: AleraTokens.space4),
            Padding(
              padding: EdgeInsets.only(left: rowLeft + AleraTokens.space20),
              child: Column(
                children: <Widget>[
                  for (final status in listedAgents)
                    _AgentPresenceRow(
                      status: status,
                      onTap: () => onAgentTap(status),
                      onClose: () => onCloseAgent(status),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

MobileWorkspacePullRequestSummary? _pullRequestSummaryFallback(
  String workspaceId,
  MobilePullRequestWatch? watch,
) {
  if (watch == null || watch.reviewNumber <= 0) {
    return null;
  }
  return MobileWorkspacePullRequestSummary(
    workspaceId: workspaceId,
    number: watch.reviewNumber,
  );
}
