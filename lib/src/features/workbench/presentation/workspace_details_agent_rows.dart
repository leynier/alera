import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/design_system/menus/alera_menu_position.dart';
import 'package:alera/src/design_system/surfaces/alera_workspace_details_card.dart';
import 'package:alera/src/design_system/surfaces/workspace_details_density.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/presentation/agent_identity_icon.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_run_groups.dart';
import 'package:alera/src/features/chat_tasks/application/chat_workspace_attention.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_status_projection.dart';
import 'package:alera/src/features/workbench/application/workspace_chat_agent_runs.dart';
import 'package:alera/src/features/workbench/application/workspace_details_agent_groups.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_panel.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/widgets/agent_run_state_indicator.dart';
import 'package:alera/src/features/workbench/presentation/widgets/agent_run_status_badge.dart';
import 'package:alera/src/features/workbench/presentation/widgets/workspace_agent_compact_summary.dart';
import 'package:alera/src/features/workbench/presentation/widgets/workspace_agent_run_icon.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Agents running in the workspace's terminals and its agent chats, each
/// delegated chat under the chat that delegated it. Renders nothing when
/// there are none, so the card keeps its height for workspaces without agents.
///
/// Starts collapsed to one row of agents grouped by state, like the sidebar.
/// Expanded, it lists the main panel's agents and then the right panel's,
/// each in Agent Activity order; with agents on both sides a divider above
/// each side collapses it on its own. Both choices are remembered per
/// workspace.
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
  @override
  Widget build(BuildContext context) {
    final id = widget.workspace.id;
    final tabs = ref
        .watch(
          workbenchControllerProvider.select(
            (state) => _AgentTabs(state.awakeTabsFor(id)),
          ),
        )
        .tabs;
    final statuses = <String, AgentStatusEntry>{
      for (final tab in tabs)
        if (tab.kind == WorkspaceTabKind.terminal)
          tab.terminalSessionId: ?ref.watch(
            agentStatusControllerProvider.select(
              (statuses) => statuses[tab.terminalSessionId],
            ),
          ),
    };
    final chats = <String, ChatAttentionEntry>{};
    for (final chatId in tabs.map((tab) => tab.agentChatId).nonNulls) {
      final entry = ref.watch(
        chatAttentionLiveProvider.select((chats) => chats[chatId]),
      );
      if (entry != null) chats[chatId] = entry;
    }
    final runs = visibleWorkspaceAgentRuns(
      tabs: tabs,
      agentStatuses: statuses,
      chats: chats,
    );
    if (runs.isEmpty) return const SizedBox.shrink();
    final panel = ref.watch(
      workbenchControllerProvider.select(
        (state) => state.viewPrefs.workspacePanels[id],
      ),
    );
    final groups = groupWorkspaceDetailsAgentRuns(
      runs,
      panel: panel,
      now: DateTime.now(),
    );
    if (widget.density == WorkspaceDetailsDensity.essential) {
      return AleraWorkspaceDetailsSection(
        children: [_header(groups.all, expanded: false, menu: true)],
      );
    }
    final fold = ref.watch(
      workbenchControllerProvider.select((state) {
        final prefs = state.viewPrefs;
        final collapsed = prefs.workspaceDetailsAgentGroupsCollapsed;
        return (
          expanded: prefs.workspaceDetailsAgentsExpandedIds.contains(id),
          main: collapsed.contains(
            workspaceDetailsAgentGroupKey(id, WorkspacePanelTree.main),
          ),
          right: collapsed.contains(
            workspaceDetailsAgentGroupKey(id, WorkspacePanelTree.right),
          ),
        );
      }),
    );
    final split = groups.main.isNotEmpty && groups.right.isNotEmpty;
    bool collapsed(WorkspacePanelTree tree) =>
        tree == WorkspacePanelTree.main ? fold.main : fold.right;
    return AleraWorkspaceDetailsSection(
      children: [
        _header(groups.all, expanded: fold.expanded),
        if (fold.expanded && !split)
          for (final run in groups.all) _row(run),
        if (fold.expanded && split)
          for (final tree in WorkspacePanelTree.values) ...[
            _divider(tree, groups.runsIn(tree), collapsed: collapsed(tree)),
            if (!collapsed(tree))
              for (final run in groups.runsIn(tree)) _row(run),
          ],
      ],
    );
  }

  Future<void> _focus(WorkspaceAgentRun run) async {
    final controller = ref.read(workbenchControllerProvider.notifier);
    await controller.selectWorkspaceTab(
      workspaceId: widget.workspace.id,
      tabId: run.tab.id,
    );
    // A chat tab focuses its own composer when it becomes active.
    if (!mounted || run.chat != null) return;
    ref
        .read(terminalRuntimeProvider)
        .sessionFor(workspace: widget.workspace, tab: run.tab)
        .requestFocus();
  }

  String _label(WorkspaceAgentRun run) {
    final title = run.tab.title.trim();
    if (run.chat case final chat?) {
      final chatTitle = chat.title.trim();
      return chatTitle.isNotEmpty
          ? chatTitle
          : title.isNotEmpty
          ? title
          : agentChatProviderFallbackLabel(chat.provider);
    }
    return run.tab.hasManualTitle && title.isNotEmpty
        ? title
        : agentDisplayName(run.status.agentType);
  }

  /// What the agent is doing or last said; the state itself is on the right.
  String _detail(WorkspaceAgentRun run) {
    if (run.chat case final chat?) {
      final tasks = chat.openChildTaskCount;
      return [
        agentChatProviderFallbackLabel(chat.provider),
        workspaceChatRunStateLabel(chat),
        if (tasks > 0) '$tasks delegated ${tasks == 1 ? 'task' : 'tasks'}',
      ].join(' · ');
    }
    final status = run.status;
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
    final chat = run.chat;
    final state = chat == null
        ? agentRunStateLabel(status)
        : workspaceChatRunStateLabel(chat);
    return AleraWorkspaceDetailControl(
      key: ValueKey(run.tab.id),
      tooltip: '${_label(run)} · $state',
      onPressed: () => unawaited(_focus(run)),
      child: Row(
        children: [
          // A delegated chat sits under the chat that delegated it.
          if ((chat?.depth ?? 0) > 0)
            SizedBox(width: chat!.depth * AleraTokens.space12),
          AleraWorkspaceDetailLeading(
            child: WorkspaceAgentRunIcon(
              run: run,
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
                    _detail(run),
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

  /// The section's single row: every agent grouped by state while
  /// collapsed, a chevron while expanded. With [menu] a press lists the
  /// agents instead, for cards too short to expand.
  Widget _header(
    List<WorkspaceAgentRun> runs, {
    required bool expanded,
    bool menu = false,
  }) {
    final label = runs.length == 1
        ? _label(runs.single)
        : '${runs.length} Agents';
    final tooltip = menu
        ? 'Agents'
        : expanded
        ? 'Hide Agents'
        : 'Show Agents';
    return AleraWorkspaceDetailControl(
      key: const ValueKey('workspace-details-agents'),
      tooltip: tooltip,
      onPressed: menu
          ? null
          : () => ref
                .read(workbenchControllerProvider.notifier)
                .toggleWorkspaceDetailsAgents(widget.workspace.id),
      onMenu: menu ? (anchor) => unawaited(_menu(runs, anchor)) : null,
      pressOpensMenu: menu,
      child: Row(
        children: [
          const AleraWorkspaceDetailLeading(child: Icon(AleraIcons.agent)),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          if (expanded)
            const Icon(
              AleraIcons.chevronDown,
              size: 12,
              color: AleraTokens.foregroundMuted,
            )
          else
            WorkspaceAgentCompactSummary(
              groups: groupWorkspaceAgentRuns(runs),
              expanded: false,
              onToggle: null,
            ),
        ],
      ),
    );
  }

  /// Unlabeled divider above one panel's agents. Pressing it collapses that
  /// panel's agents into a state-grouped summary.
  Widget _divider(
    WorkspacePanelTree tree,
    List<WorkspaceAgentRun> runs, {
    required bool collapsed,
  }) {
    final side = tree == WorkspacePanelTree.main ? 'Main Panel' : 'Right Panel';
    return AleraWorkspaceDetailSegment(
      key: ValueKey('workspace-details-agents-${tree.name}'),
      tooltip: collapsed ? 'Show $side Agents' : 'Hide $side Agents',
      onPressed: () => ref
          .read(workbenchControllerProvider.notifier)
          .toggleWorkspaceDetailsAgentGroup(widget.workspace.id, tree),
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space8,
        vertical: AleraTokens.space4,
      ),
      child: Row(
        children: [
          const Expanded(
            child: Divider(
              height: AleraTokens.dividerExtent,
              thickness: AleraTokens.dividerExtent,
              color: AleraTokens.borderSubtle,
            ),
          ),
          const SizedBox(width: AleraTokens.space6),
          if (collapsed)
            WorkspaceAgentCompactSummary(
              groups: groupWorkspaceAgentRuns(runs),
              expanded: false,
              onToggle: null,
            )
          else
            const Icon(
              AleraIcons.chevronDown,
              size: 12,
              color: AleraTokens.foregroundMuted,
            ),
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
            detail: run.chat == null
                ? agentRunStateLabel(run.status)
                : workspaceChatRunStateLabel(run.chat!),
            leading: WorkspaceAgentRunIcon(
              run: run,
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

/// Terminal and agent chat tabs compared by the fields the agent rows show,
/// so unrelated workbench changes do not rebuild the section.
class const _AgentTabs(final List<WorkspaceTabRecord> all) {
  List<WorkspaceTabRecord> get tabs => [
    for (final tab in all)
      if (tab.kind == WorkspaceTabKind.terminal ||
          tab.kind == WorkspaceTabKind.agentChat)
        tab,
  ];

  List<(String, String, String, bool, String?)> get _key => [
    for (final tab in tabs)
      (
        tab.id,
        tab.terminalSessionId,
        tab.title,
        tab.hasManualTitle,
        tab.agentChatId,
      ),
  ];

  @override
  bool operator ==(Object other) =>
      other is _AgentTabs && listEquals(_key, other._key);

  @override
  int get hashCode => Object.hashAll(_key);
}
