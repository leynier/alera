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
class WorkspaceAgentCompactSummary extends StatelessWidget {
  const WorkspaceAgentCompactSummary({
    super.key,
    required this.groups,
    required this.expanded,
    required this.onToggle,
    this.tooltipOverride,
  });

  final List<WorkspaceAgentRunGroup> groups;
  final bool expanded;
  final VoidCallback onToggle;

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
        tooltipOverride ??
        (expanded ? 'Hide Agent Runs' : 'Show Agent Runs');
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onToggle,
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space4,
            vertical: AleraTokens.space2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
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
        const SizedBox(width: AleraTokens.space2),
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

List<WorkspaceAgentRun> _representativeRunsByAgentType(
  List<WorkspaceAgentRun> runs,
) {
  final seen = <AgentType>{};
  return <WorkspaceAgentRun>[
    for (final run in runs)
      if (seen.add(run.status.agentType)) run,
  ];
}
