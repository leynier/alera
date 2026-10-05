import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/forms/alera_search_field.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/linked_issues/application/linked_issues_controller.dart';
import 'package:alera_mobile/src/features/pull_requests/application/pull_request_watch_controller.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_view_prefs_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_workspace_rows.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_agent_expansion_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_hosts_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_pull_request_summaries_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_search_controller.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/workbench/presentation/mobile_section_header.dart';
import 'package:alera_mobile/src/features/workbench/presentation/section_picker_sheet.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_actions_sheet.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_agent_terminal_actions.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_row_widgets.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_view_options_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Scrolling workspace list for one host: pull-to-refresh over the list and
/// the pull request summaries together, the search toolbar, and every
/// workspace row mirroring the desktop sidebar anatomy.
class const RuntimeWorkspacesListBody({
  super.key,
  required final String hostId,
  required final WorkspaceListData data,
  required final MobileViewPrefs prefs,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expandedWorkspaceIds =
        ref.watch(workspaceAgentExpansionControllerProvider(hostId)).value ??
        const <String>{};
    final linkedIssues = ref
        .watch(linkedIssuesControllerProvider(hostId))
        .value
        ?.byWorkspace;
    final pullRequestSummaries = ref
        .watch(workspacePullRequestSummariesControllerProvider(hostId))
        .value;
    final pullRequestWatches = ref
        .watch(pullRequestWatchControllerProvider(hostId))
        .value;
    final workspaceHosts = ref
        .watch(workspaceHostsControllerProvider(hostId))
        .value;
    final searchQuery = ref.watch(workspaceSearchControllerProvider(hostId));
    final rows = buildMobileWorkspaceRows(
      sections: data.sections,
      workspaces: data.workspaces,
      projects: data.projects,
      prefs: prefs,
      activity: data.activity,
      agentPresence: data.agentPresence,
      terminalTabCountByWorkspaceId: data.terminalTabCountByWorkspaceId,
      searchQuery: searchQuery,
    );
    final noSearchMatches =
        searchQuery.trim().isNotEmpty && !rows.any(_rowHasWorkspaces);
    final agentPresenceByWorkspaceId = <String, List<AgentPresenceSummary>>{};
    for (final status in data.agentPresence) {
      agentPresenceByWorkspaceId
          .putIfAbsent(status.workspaceId, () => <AgentPresenceSummary>[])
          .add(status);
    }
    final prefsController = ref.read(
      mobileViewPrefsControllerProvider(hostId).notifier,
    );
    return RefreshIndicator(
      onRefresh: () => refreshWorkspaceList(ref, hostId),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverAppBar(
            floating: true,
            snap: true,
            pinned: false,
            primary: false,
            automaticallyImplyLeading: false,
            backgroundColor: AleraTokens.bg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            toolbarHeight: RuntimeWorkspacesToolbar.extent,
            titleSpacing: 0,
            centerTitle: false,
            title: SizedBox(
              width: .infinity,
              child: RuntimeWorkspacesToolbar(hostId: hostId, data: data),
            ),
          ),
          if (noSearchMatches)
            SliverFillRemaining(
              hasScrollBody: false,
              child: AleraEmptyState(
                icon: AleraIcons.searchEmpty,
                title: 'No matching workspaces',
                message: 'No workspace matches "${searchQuery.trim()}".',
                action: OutlinedButton(
                  onPressed: ref
                      .read(workspaceSearchControllerProvider(hostId).notifier)
                      .clear,
                  child: const Text('Clear Search'),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(bottom: AleraTokens.spaceXxl * 2),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final row = rows[index];
                  return switch (row) {
                    MobileCustomSectionHeaderRow() => MobileCustomSectionHeader(
                      hostId: hostId,
                      row: row,
                      supportsSections: data.supportsSections,
                    ),
                    MobilePinnedHeaderRow(:final count, :final collapsed) =>
                      MobileSectionHeader(
                        label: 'Pinned',
                        icon: AleraIcons.pin,
                        count: count,
                        collapsed: collapsed,
                        onToggle: prefsController.togglePinnedSection,
                      ),
                    MobileProjectHeaderRow(
                      :final projectId,
                      :final projectName,
                      :final count,
                      :final collapsed,
                    ) =>
                      MobileSectionHeader(
                        label: projectName,
                        icon: collapsed
                            ? AleraIcons.folder
                            : AleraIcons.folderOpen,
                        count: count,
                        collapsed: collapsed,
                        onToggle: () =>
                            prefsController.toggleProjectCollapsed(projectId),
                      ),
                    MobileAllHeaderRow(:final count, :final collapsed) =>
                      MobileSectionHeader(
                        label: 'All',
                        icon: AleraIcons.listView,
                        count: count,
                        collapsed: collapsed,
                        onToggle: prefsController.toggleAllSection,
                      ),
                    MobileWorkspaceEntryRow() => MobileWorkspaceListRow(
                      row: row,
                      linkedIssue: linkedIssues?[row.entry.workspace.id],
                      pullRequestSummary:
                          pullRequestSummaries?[row.entry.workspace.id],
                      pullRequestWatch: pullRequestWatches
                          ?.byWorkspace[row.entry.workspace.id],
                      host: workspaceHosts?.hostOf(row.entry.workspace),
                      terminalTabCount:
                          data.terminalTabCountByWorkspaceId[row
                              .entry
                              .workspace
                              .id] ??
                          0,
                      agentPresence:
                          agentPresenceByWorkspaceId[row.entry.workspace.id] ??
                          const <AgentPresenceSummary>[],
                      mainTabIds: {
                        ...?data.workspaceMainTabIds[row.entry.workspace.id],
                      },
                      agentsExpanded: expandedWorkspaceIds.contains(
                        row.entry.workspace.id,
                      ),
                      onToggleAgents: () => ref
                          .read(
                            workspaceAgentExpansionControllerProvider(hostId)
                                .notifier,
                          )
                          .toggle(row.entry.workspace.id),
                      onAgentTap: (status) {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => WorkspaceTabsScreen(
                              hostId: hostId,
                              workspace: row.entry.workspace,
                              initialTabId: status.tabId,
                            ),
                          ),
                        );
                      },
                      onCloseAgent: (status) => closeWorkspaceAgentTerminal(
                        context,
                        ref,
                        status,
                        hostId: hostId,
                        workspaceId: row.entry.workspace.id,
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => WorkspaceTabsScreen(
                              hostId: hostId,
                              workspace: row.entry.workspace,
                            ),
                          ),
                        );
                      },
                      onLongPress: () => showWorkspaceActionsSheet(
                        context,
                        ref,
                        hostId: hostId,
                        workspace: row.entry.workspace,
                        data: data,
                      ),
                      onMore: () => showWorkspaceActionsSheet(
                        context,
                        ref,
                        hostId: hostId,
                        workspace: row.entry.workspace,
                        data: data,
                      ),
                      onToggleChildren: () => prefsController
                          .toggleParentCollapsed(row.entry.workspace.id),
                    ),
                  };
                }, childCount: rows.length),
              ),
            ),
        ],
      ),
    );
  }
}

/// Whether [row] stands for at least one visible workspace, including the
/// collapsed ones a header still counts.
bool _rowHasWorkspaces(MobileWorkspaceRow row) => switch (row) {
  MobileWorkspaceEntryRow() => true,
  MobileCustomSectionHeaderRow(:final count) ||
  MobilePinnedHeaderRow(:final count) ||
  MobileProjectHeaderRow(:final count) ||
  MobileAllHeaderRow(:final count) => count > 0,
};

/// Reloads the workspace list together with the pull request summaries, watch
/// state, and host directory that decorate its rows.
Future<void> refreshWorkspaceList(WidgetRef ref, String hostId) async {
  ref.invalidate(workspaceListControllerProvider(hostId));
  ref.invalidate(workspacePullRequestSummariesControllerProvider(hostId));
  ref.invalidate(pullRequestWatchControllerProvider(hostId));
  ref.invalidate(workspaceHostsControllerProvider(hostId));
  await ref.read(workspaceListControllerProvider(hostId).future);
  await ref.read(
    workspacePullRequestSummariesControllerProvider(hostId).future,
  );
  await ref.read(pullRequestWatchControllerProvider(hostId).future);
  await ref.read(workspaceHostsControllerProvider(hostId).future);
}

/// Fills the space below the toolbar with [child] while staying scrollable,
/// so the empty and error states still answer pull-to-refresh.
class const WorkspaceListPlaceholder({super.key, required final Widget child})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: <Widget>[
        SliverFillRemaining(hasScrollBody: false, child: child),
      ],
    );
  }
}

/// Dense search row driving [RuntimeWorkspacesListBody]'s floating toolbar.
/// Shared with the screen's empty, error, and loading states.
class const RuntimeWorkspacesToolbar({
  super.key,
  required final String hostId,
  required final WorkspaceListData? data,
}) extends ConsumerStatefulWidget {
  /// Dense search row plus vertical padding; drives the sliver toolbar height.
  static const double extent =
      AleraTextField.denseHeight + AleraTokens.spaceSm * 2;

  @override
  ConsumerState<RuntimeWorkspacesToolbar> createState() =>
      _RuntimeWorkspacesToolbarState();
}

class _RuntimeWorkspacesToolbarState
    extends ConsumerState<RuntimeWorkspacesToolbar> {
  // Seeded from the query so a toolbar remounted by a state change keeps the
  // text that is still filtering the list.
  late final TextEditingController _query = TextEditingController(
    text: ref.read(workspaceSearchControllerProvider(widget.hostId)),
  );

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hostId = widget.hostId;
    final data = widget.data;
    ref.listen(workspaceSearchControllerProvider(hostId), (previous, next) {
      if (next.isEmpty && _query.text.isNotEmpty) {
        _query.clear();
      }
    });
    final controller = ref.read(
      workspaceSearchControllerProvider(hostId).notifier,
    );
    return SizedBox(
      height: RuntimeWorkspacesToolbar.extent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AleraTokens.spaceMd,
          AleraTokens.spaceSm,
          AleraTokens.spaceSm,
          AleraTokens.spaceSm,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: AleraSearchField(
                controller: _query,
                dense: true,
                hintText: 'Search workspaces',
                onChanged: controller.setQuery,
              ),
            ),
            const SizedBox(width: AleraTokens.spaceSm),
            AleraIconButton(
              tooltip: 'View Options',
              onPressed: data == null
                  ? null
                  : () => showWorkspaceViewOptionsSheet(
                      context,
                      ref,
                      hostId: hostId,
                      data: data,
                    ),
              icon: AleraIcons.tune,
              backgroundColor: AleraTokens.surfaceVariant,
              borderColor: AleraTokens.border,
            ),
          ],
        ),
      ),
    );
  }
}
