import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/presentation/agent_identity_icon.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_run_groups.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_status_projection.dart';
import 'package:alera/src/features/workbench/presentation/widgets/agent_run_state_indicator.dart';
import 'package:flutter/material.dart';

/// Compact tray control for a workspace's agent runs: agents grouped by state,
/// each group showing its state glyph plus up to three overlapping identity
/// icons. Clicking toggles the expanded per-agent rows under the workspace.
class const WorkspaceAgentCompactSummary({
  super.key,
  required final List<WorkspaceAgentRunGroup> groups,
  required final bool expanded,
  required final VoidCallback onToggle,
  this.tooltipOverride,
}) extends StatelessWidget {
  /// Optional tooltip; defaults to Show/Hide Agent Runs.
  final String? tooltipOverride;

  static const int _maxVisibleGroups = 3;
  static const int _maxIconsPerGroup = 3;
  static const double _iconSize = 14;
  static const double _iconOverlap = 4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleGroups = groups.take(_maxVisibleGroups).toList();
    final hiddenGroupRuns = groups
        .skip(_maxVisibleGroups)
        .fold<int>(0, (sum, group) => sum + group.runs.length);
    final tooltip =
        tooltipOverride ?? (expanded ? 'Hide Agent Runs' : 'Show Agent Runs');
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onToggle,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: .circular(AleraTokens.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space4,
            vertical: AleraTokens.space2,
          ),
          child: Row(
            mainAxisSize: .min,
            children: <Widget>[
              for (final (index, group) in visibleGroups.indexed) ...<Widget>[
                if (index > 0) const SizedBox(width: AleraTokens.space6),
                _GroupCluster(group: group),
              ],
              if (hiddenGroupRuns > 0) ...<Widget>[
                const SizedBox(width: AleraTokens.space4),
                Text(
                  '+$hiddenGroupRuns',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundFaint,
                  ),
                ),
              ],
              const SizedBox(width: AleraTokens.space2),
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

class const _GroupCluster({required final WorkspaceAgentRunGroup group})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const iconSize = WorkspaceAgentCompactSummary._iconSize;
    const overlap = WorkspaceAgentCompactSummary._iconOverlap;
    final iconRuns = _representativeRunsByAgentType(group.runs)
        .take(WorkspaceAgentCompactSummary._maxIconsPerGroup)
        .toList();
    final hiddenCount = group.runs.length - iconRuns.length;
    final width = iconSize + (iconRuns.length - 1) * (iconSize - overlap);
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        AgentRunStateIndicator(status: group.runs.first.status, size: 11),
        const SizedBox(width: AleraTokens.space2),
        SizedBox(
          width: width,
          height: iconSize,
          child: Stack(
            children: <Widget>[
              for (final (index, run) in iconRuns.indexed)
                Positioned(
                  key: ValueKey<AgentType>(run.status.agentType),
                  left: index * (iconSize - overlap),
                  child: Container(
                    width: iconSize,
                    height: iconSize,
                    decoration: BoxDecoration(
                      color: AleraTokens.surfaceVariant,
                      shape: .circle,
                      border: Border.all(color: AleraTokens.borderSubtle),
                    ),
                    child: Center(
                      child: AgentIdentityIcon(
                        agentType: run.status.agentType,
                        size: 9,
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

/// One run per agent type, ordered by agent type rather than by the run order.
///
/// Runs arrive in creation order; sorting the representatives by agent type
/// keeps a group's icons in a fixed order regardless of status churn.
List<WorkspaceAgentRun> _representativeRunsByAgentType(
  List<WorkspaceAgentRun> runs,
) {
  final seen = <AgentType>{};
  final representatives = <WorkspaceAgentRun>[
    for (final run in runs)
      if (seen.add(run.status.agentType)) run,
  ];
  representatives.sort(
    (a, b) => a.status.agentType.index.compareTo(b.status.agentType.index),
  );
  return representatives;
}
