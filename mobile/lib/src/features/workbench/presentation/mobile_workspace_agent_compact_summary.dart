import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_agent_run_groups.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_identity_icon.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_run_state_indicator.dart';
import 'package:flutter/material.dart';

/// Compact tray control for a workspace's agent runs: agents grouped by state,
/// each group showing its state glyph plus up to three overlapping identity
/// icons. Tapping toggles the expanded per-agent rows under the workspace.
class const MobileWorkspaceAgentCompactSummary({
  super.key,
  required final List<WorkspaceAgentRunGroup> groups,
  required final bool expanded,
  required final VoidCallback onToggle,
  this.tooltipOverride,
  this.fillHeight = false,
}) extends StatelessWidget {
  /// Optional tooltip; defaults to Show/Hide Agent Runs.
  final String? tooltipOverride;

  /// When true, the tap target stretches to the parent row height.
  final bool fillHeight;

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
    final content = Row(
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
    );
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onToggle,
        borderRadius: .circular(AleraTokens.radiusSm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: AleraTokens.minTapTarget),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AleraTokens.space8,
              vertical: fillHeight ? 0 : AleraTokens.space2,
            ),
            child: fillHeight ? Center(child: content) : content,
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
    const iconSize = MobileWorkspaceAgentCompactSummary._iconSize;
    const overlap = MobileWorkspaceAgentCompactSummary._iconOverlap;
    final iconRuns = _representativeRunsByAgentType(group.runs)
        .take(MobileWorkspaceAgentCompactSummary._maxIconsPerGroup)
        .toList();
    final hiddenCount = group.runs.length - iconRuns.length;
    final width = iconSize + (iconRuns.length - 1) * (iconSize - overlap);
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        AgentRunStateIndicator(status: group.runs.first, size: 11),
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
                      shape: .circle,
                      border: Border.all(color: AleraTokens.borderSubtle),
                    ),
                    child: Center(
                      child: AgentIdentityIcon(
                        agentType: run.agentType,
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

List<AgentPresenceSummary> _representativeRunsByAgentType(
  List<AgentPresenceSummary> runs,
) {
  final seen = <String>{};
  return <AgentPresenceSummary>[
    for (final run in runs)
      if (seen.add(run.agentType)) run,
  ];
}
