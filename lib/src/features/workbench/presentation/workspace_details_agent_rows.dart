import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/design_system/menus/alera_menu_position.dart';
import 'package:alera/src/design_system/surfaces/alera_workspace_details_card.dart';
import 'package:alera/src/design_system/surfaces/workspace_details_density.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/presentation/agent_identity_icon.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_status_projection.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/widgets/agent_run_state_indicator.dart';
import 'package:alera/src/features/workbench/presentation/widgets/agent_run_status_badge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Agents running in the workspace's terminals. Renders nothing when there
/// are none, so the card keeps its height for workspaces without agents.
class const WorkspaceDetailsAgentRows({
  super.key,
  required this.workspace,
  required this.density,
}) extends ConsumerStatefulWidget {
  final Workspace workspace;
  final WorkspaceDetailsDensity density;
  @override
  ConsumerState<WorkspaceDetailsAgentRows> createState() =>
      _WorkspaceDetailsAgentRowsState();
}

class _WorkspaceDetailsAgentRowsState
    extends ConsumerState<WorkspaceDetailsAgentRows> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final id = widget.workspace.id;
    final tabs = ref
        .watch(
          workbenchControllerProvider.select(
            (state) => _TerminalTabs(state.awakeTabsFor(id)),
          ),
        )
        .tabs;
    final statuses = <String, AgentStatusEntry>{
      for (final tab in tabs)
        tab.terminalSessionId: ?ref.watch(
          agentStatusControllerProvider.select(
            (statuses) => statuses[tab.terminalSessionId],
          ),
        ),
    };
    final runs = visibleWorkspaceAgentRuns(tabs: tabs, agentStatuses: statuses);
    if (runs.isEmpty) return const SizedBox.shrink();
    if (widget.density == WorkspaceDetailsDensity.essential) {
      return AleraWorkspaceDetailsSection(children: [_summary(runs)]);
    }
    final limit = widget.density == WorkspaceDetailsDensity.full ? 4 : 3;
    final shown = _expanded || runs.length <= limit
        ? runs
        : runs.take(limit - 1).toList();
    return AleraWorkspaceDetailsSection(
      children: [
        for (final run in shown) _row(run),
        if (runs.length > limit) _toggle(runs.length - shown.length),
      ],
    );
  }

  Future<void> _focus(WorkspaceAgentRun run) async {
    final controller = ref.read(workbenchControllerProvider.notifier);
    await controller.selectWorkspaceTab(
      workspaceId: widget.workspace.id,
      tabId: run.tab.id,
    );
    if (!mounted) return;
    ref
        .read(terminalRuntimeProvider)
        .sessionFor(workspace: widget.workspace, tab: run.tab)
        .requestFocus();
  }

  String _label(WorkspaceAgentRun run) {
    final title = run.tab.title.trim();
    return run.tab.hasManualTitle && title.isNotEmpty
        ? title
        : agentDisplayName(run.status.agentType);
  }

  /// What the agent is doing or last said; the state itself is on the right.
  String _detail(AgentStatusEntry status) {
    final working = status.state == AgentStatusState.working;
    final candidates = [
      working ? status.toolName : status.lastAssistantMessage,
      status.prompt,
    ];
    for (final text in candidates) {
      final line = text?.trim().split('\n').first.trim() ?? '';
      if (line.isNotEmpty) return line;
    }
    return agentRunStateLabel(status);
  }

  Widget _row(WorkspaceAgentRun run) {
    final theme = Theme.of(context);
    final status = run.status;
    final full = widget.density == WorkspaceDetailsDensity.full;
    return AleraWorkspaceDetailControl(
      key: ValueKey(run.tab.id),
      tooltip: '${_label(run)} · ${agentRunStateLabel(status)}',
      onPressed: () => unawaited(_focus(run)),
      child: Row(
        children: [
          AleraWorkspaceDetailLeading(
            child: AgentIdentityIcon(
              agentType: status.agentType,
              size: AleraTokens.iconMd,
              showTooltip: false,
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _label(run),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AleraTokens.foreground,
                  ),
                ),
                if (full)
                  Text(
                    _detail(status),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          if (agentRunStatusBadge(status) != null)
            AgentRunStatusBadge(status: status)
          else
            AgentRunStateIndicator(status: status),
        ],
      ),
    );
  }

  Widget _toggle(int hidden) {
    final label = _expanded ? 'Show Fewer Agents' : 'Show $hidden More';
    return AleraWorkspaceDetailControl(
      tooltip: label,
      onPressed: () => setState(() => _expanded = !_expanded),
      child: Row(
        children: [
          AleraWorkspaceDetailLeading(
            child: Icon(_expanded ? AleraIcons.remove : AleraIcons.add),
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: AleraTokens.foregroundMuted),
            ),
          ),
        ],
      ),
    );
  }

  /// One row for the whole set: the most urgent agent leads, the menu lists
  /// every agent.
  Widget _summary(List<WorkspaceAgentRun> runs) {
    final urgent = mostUrgentWorkspaceAgentRun(runs) ?? runs.first;
    final label = runs.length == 1 ? _label(urgent) : '${runs.length} Agents';
    return AleraWorkspaceDetailControl(
      tooltip: '$label · ${agentRunStateLabel(urgent.status)}',
      onPressed: () => unawaited(_focus(urgent)),
      onMenu: (anchor) => unawaited(_menu(runs, anchor)),
      menuTooltip: 'Agents',
      child: Row(
        children: [
          AleraWorkspaceDetailLeading(
            child: AgentIdentityIcon(
              agentType: urgent.status.agentType,
              size: AleraTokens.iconMd,
              showTooltip: false,
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          AgentRunStateIndicator(status: urgent.status),
        ],
      ),
    );
  }

  Future<void> _menu(List<WorkspaceAgentRun> runs, Rect anchor) async {
    final choice = await showMenu<String>(
      context: context,
      position: aleraMenuBelow(context, anchor),
      items: [
        for (final run in runs)
          AleraDropdownEntry(
            value: run.tab.id,
            label: _label(run),
            detail: agentRunStateLabel(run.status),
            leading: AgentIdentityIcon(
              agentType: run.status.agentType,
              size: AleraTokens.iconMd,
              showTooltip: false,
            ),
          ),
      ],
    );
    if (!mounted || choice == null) return;
    final run = runs.where((run) => run.tab.id == choice).firstOrNull;
    if (run != null) await _focus(run);
  }
}

/// Terminal tabs compared by the fields the agent rows show, so unrelated
/// workbench changes do not rebuild the section.
class const _TerminalTabs(final List<WorkspaceTabRecord> all) {
  List<WorkspaceTabRecord> get tabs => [
    for (final tab in all)
      if (tab.kind == WorkspaceTabKind.terminal) tab,
  ];

  List<(String, String, String, bool)> get _key => [
    for (final tab in tabs)
      (tab.id, tab.terminalSessionId, tab.title, tab.hasManualTitle),
  ];

  @override
  bool operator ==(Object other) =>
      other is _TerminalTabs && listEquals(_key, other._key);

  @override
  int get hashCode => Object.hashAll(_key);
}
