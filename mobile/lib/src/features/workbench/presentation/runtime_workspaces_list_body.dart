import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/forms/alera_search_field.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/linked_issues/application/linked_issues_controller.dart';
import 'package:alera_mobile/src/features/pull_requests/application/pull_request_watch_controller.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_view_prefs_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_workspace_rows.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_agent_expansion_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_pull_request_summaries_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_search_controller.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';
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
    final rows = buildMobileWorkspaceRows(
      sections: data.sections,
      workspaces: data.workspaces,
      projects: data.projects,
      prefs: prefs,
      activity: data.activity,
      agentPresence: data.agentPresence,
      terminalTabCountByWorkspaceId: data.terminalTabCountByWorkspaceId,
      searchQuery: ref.watch(workspaceSearchControllerProvider(hostId)),
    );
    final prefsController = ref.read(
      mobileViewPrefsControllerProvider(hostId).notifier,
    );
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(workspaceListControllerProvider(hostId));
        ref.invalidate(workspacePullRequestSummariesControllerProvider(hostId));
        ref.invalidate(pullRequestWatchControllerProvider(hostId));
        await ref.read(workspaceListControllerProvider(hostId).future);
        await ref.read(
          workspacePullRequestSummariesControllerProvider(hostId).future,
        );
        await ref.read(pullRequestWatchControllerProvider(hostId).future);
      },
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
                    pullRequestWatch:
                        pullRequestWatches?.byWorkspace[row.entry.workspace.id],
                    terminalTabCount:
                        data.terminalTabCountByWorkspaceId[row
                            .entry
                            .workspace
                            .id] ??
                        0,
                    agentPresence: data.agentPresence
                        .where(
                          (status) =>
                              status.workspaceId == row.entry.workspace.id,
                        )
                        .toList(),
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

/// Dense search row driving [RuntimeWorkspacesListBody]'s floating toolbar.
/// Shared with the screen's empty, error, and loading states.
class const RuntimeWorkspacesToolbar({
  super.key,
  required final String hostId,
  required final WorkspaceListData? data,
}) extends ConsumerWidget {
  /// Dense search row plus vertical padding; drives the sliver toolbar height.
  static const double extent =
      AleraTextField.denseHeight + AleraTokens.spaceSm * 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(
      workspaceSearchControllerProvider(hostId).notifier,
    );
    return SizedBox(
      height: extent,
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
                      data: data!,
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
