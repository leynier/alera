import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_workspace_rows.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_agent_run_groups.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_identity_icon.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_run_state_indicator.dart';
import 'package:alera_mobile/src/features/workbench/presentation/mobile_workspace_agent_compact_summary.dart';
import 'package:flutter/material.dart';

part 'workspace_row_trays.dart';

/// Dense single-line workspace row mirroring the desktop sidebar anatomy.
class MobileWorkspaceListRow extends StatelessWidget {
  const MobileWorkspaceListRow({
    super.key,
    required this.row,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
    required this.onToggleChildren,
    required this.terminalTabCount,
    required this.agentsExpanded,
    required this.onToggleAgents,
    required this.onAgentTap,
    required this.onCloseAgent,
    this.agentPresence = const <AgentPresenceSummary>[],
    this.showProjectIcon = false,
    this.projectName,
  });

  final MobileWorkspaceEntryRow row;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;
  final VoidCallback onToggleChildren;
  final int terminalTabCount;
  final bool agentsExpanded;
  final VoidCallback onToggleAgents;
  final ValueChanged<AgentPresenceSummary> onAgentTap;
  final ValueChanged<AgentPresenceSummary> onCloseAgent;
  final List<AgentPresenceSummary> agentPresence;
  final bool showProjectIcon;
  final String? projectName;

  /// Fixed leading slot so status glyphs do not shift the title (desktop: 14).
  static const double _statusSlotSize = 14;
  static const double _trayIconSize = 12;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = row.entry;
    final workspace = entry.workspace;
    final tags = _tagLabels(workspace);
    final depthPad = (row.isPinnedCopy ? 0 : entry.depth) * AleraTokens.space12;
    final rowLeft = AleraTokens.space12 + depthPad;
    final canToggleChildren = !row.isPinnedCopy && entry.hasVisibleChildren;
    final hasAgents = agentPresence.isNotEmpty;
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
          message: 'Default workspace',
          child: Icon(
            AleraIcons.workspaceMain,
            size: _trayIconSize,
            color: AleraTokens.foregroundMuted,
          ),
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
      if (tags.isNotEmpty) ...<Widget>[
        const SizedBox(width: AleraTokens.space6),
        Tooltip(
          message: tags.join(', '),
          child: Row(
            mainAxisSize: MainAxisSize.min,
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
                  fontWeight: FontWeight.w600,
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: InkWell(
                    onTap: onTap,
                    onLongPress: onLongPress,
                    borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
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
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Flexible(
                                      child: Text(
                                        workspace.name,
                                        maxLines: 1,
                                        softWrap: false,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: AleraTokens.foreground,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                    ...metadataIcons,
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (hasAgents || canToggleChildren)
                  _WorkspaceActionTray(
                    childCount: entry.visibleChildCount,
                    childrenCollapsed: entry.childrenCollapsed,
                    onToggleChildren: canToggleChildren
                        ? onToggleChildren
                        : null,
                    statuses: agentPresence,
                    agentsExpanded: agentsExpanded,
                    onToggleAgents: hasAgents ? onToggleAgents : null,
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
          if (hasAgents && agentsExpanded) ...<Widget>[
            const SizedBox(height: AleraTokens.space4),
            Padding(
              padding: EdgeInsets.only(left: rowLeft + AleraTokens.space20),
              child: Column(
                children: <Widget>[
                  for (final status in agentPresence)
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
