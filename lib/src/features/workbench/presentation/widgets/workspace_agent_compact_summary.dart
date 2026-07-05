import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/presentation/agent_identity_icon.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_run_groups.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_status_projection.dart';
import 'package:alera/src/features/workbench/presentation/widgets/agent_run_state_indicator.dart';
import 'package:flutter/material.dart';

/// Single-line summary of a workspace's agent runs: agents grouped by state,
/// each group showing its state glyph plus up to three overlapping identity
/// icons. Clicking toggles the expanded per-agent rows.
class WorkspaceAgentCompactSummary extends StatelessWidget {
  const WorkspaceAgentCompactSummary({
    super.key,
    required this.groups,
    required this.expanded,
    required this.onToggle,
  });

  final List<WorkspaceAgentRunGroup> groups;
  final bool expanded;
  final VoidCallback onToggle;

  static const int _maxVisibleGroups = 3;
  static const int _maxIconsPerGroup = 3;
  static const double _iconSize = 16;
  static const double _iconOverlap = 5;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final agentCount = groups.fold<int>(
      0,
      (count, group) => count + group.runs.length,
    );
    final visibleGroups = groups.take(_maxVisibleGroups).toList();
    final hiddenGroupRuns = groups
        .skip(_maxVisibleGroups)
        .fold<int>(0, (sum, group) => sum + group.runs.length);
    return Tooltip(
      message: expanded ? 'Hide Agent Runs' : 'Show Agent Runs',
      child: InkWell(
        onTap: onToggle,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space6,
            vertical: AleraTokens.space2,
          ),
          decoration: BoxDecoration(
            color: AleraTokens.surface,
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            border: Border.all(color: AleraTokens.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: <Widget>[
              if (expanded)
                Expanded(
                  child: Text(
                    '$agentCount Agents',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Expanded(
                  child: Row(
                    children: <Widget>[
                      for (final (index, group)
                          in visibleGroups.indexed) ...<Widget>[
                        if (index > 0)
                          const SizedBox(width: AleraTokens.space8),
                        _GroupCluster(group: group),
                      ],
                      if (hiddenGroupRuns > 0) ...<Widget>[
                        const SizedBox(width: AleraTokens.space6),
                        Text(
                          '+$hiddenGroupRuns',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: AleraTokens.foregroundFaint,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(width: AleraTokens.space6),
              Icon(
                expanded ? AleraIcons.chevronUp : AleraIcons.chevronDown,
                size: 12,
                color: AleraTokens.foregroundMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupCluster extends StatelessWidget {
  const _GroupCluster({required this.group});

  final WorkspaceAgentRunGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const iconSize = WorkspaceAgentCompactSummary._iconSize;
    const overlap = WorkspaceAgentCompactSummary._iconOverlap;
    final iconRuns = _representativeRunsByAgentType(
      group.runs,
    ).take(WorkspaceAgentCompactSummary._maxIconsPerGroup).toList();
    final hiddenCount = group.runs.length - iconRuns.length;
    final width = iconSize + (iconRuns.length - 1) * (iconSize - overlap);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AgentRunStateIndicator(status: group.runs.first.status, size: 11),
        const SizedBox(width: AleraTokens.space4),
        SizedBox(
          width: width,
          height: iconSize,
          child: Stack(
            children: <Widget>[
              for (final (index, run) in iconRuns.indexed)
                Positioned(
                  left: index * (iconSize - overlap),
                  child: Container(
                    width: iconSize,
                    height: iconSize,
                    decoration: BoxDecoration(
                      color: AleraTokens.surfaceVariant,
                      shape: BoxShape.circle,
                      border: Border.all(color: AleraTokens.borderSubtle),
                    ),
                    child: Center(
                      child: AgentIdentityIcon(
                        agentType: run.status.agentType,
                        size: 10,
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (hiddenCount > 0) ...<Widget>[
          const SizedBox(width: AleraTokens.space2),
          Text(
            '+$hiddenCount',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AleraTokens.foregroundFaint,
            ),
          ),
        ],
      ],
    );
  }
}

List<WorkspaceAgentRun> _representativeRunsByAgentType(
  List<WorkspaceAgentRun> runs,
) {
  final seen = <AgentType>{};
  return <WorkspaceAgentRun>[
    for (final run in runs)
      if (seen.add(run.status.agentType)) run,
  ];
}
