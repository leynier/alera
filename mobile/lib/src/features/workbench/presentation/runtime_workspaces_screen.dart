import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera_mobile/src/design_system/forms/alera_search_field.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/hosts/presentation/rename_host_dialog.dart';
import 'package:alera_mobile/src/features/projects/presentation/projects_screen.dart';
import 'package:alera_mobile/src/features/quotas/presentation/agent_quotas_screen.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_probe.dart';
import 'package:alera_mobile/src/features/runtime/presentation/host_dashboard_screen.dart';
import 'package:alera_mobile/src/features/settings/presentation/host_settings_screen.dart';
import 'package:alera_mobile/src/features/terminal/presentation/workspace_tabs_screen.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_view_prefs_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_workspace_rows.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_agent_expansion_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_search_controller.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';
import 'package:alera_mobile/src/features/workbench/presentation/create_workspace_screen.dart';
import 'package:alera_mobile/src/features/workbench/presentation/mobile_section_header.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_actions_sheet.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_agent_terminal_actions.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_row_widgets.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_view_options_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _ScreenMenuAction { projects, quotas, settings, hostDetails, renameHost }

/// Host detail screen: the workspace list mirroring the desktop sidebar,
/// with pinning, project grouping, and the parent/child tree.
class RuntimeWorkspacesScreen extends ConsumerWidget {
  const RuntimeWorkspacesScreen({super.key, required this.host});

  final PairedHostProfile host;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(workspaceListControllerProvider(host.id));
    final prefs = ref.watch(mobileViewPrefsControllerProvider(host.id));
    final connection = ref.watch(hostConnectionControllerProvider(host.id));
    // Mounted here because this screen already keeps the connection alive
    // underneath the terminal, so the probe outlives the terminal screen.
    ref.watch(hostConnectionProbeProvider(host.id));
    final currentHost =
        ref
            .watch(pairedHostsControllerProvider)
            .value
            ?.where((profile) => profile.id == host.id)
            .firstOrNull ??
        host;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            Text(currentHost.effectiveName, overflow: TextOverflow.ellipsis),
            Positioned(
              right: -AleraTokens.space12,
              top: -AleraTokens.space2,
              child: AleraStatusDot(
                // Riverpod keeps the previous value on an error state, so
                // hasValue alone would keep the dot green on a dead socket.
                active: connection.hasValue && !connection.hasError,
                size: AleraTokens.spaceSm,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          PopupMenuButton<_ScreenMenuAction>(
            onSelected: (action) =>
                _handleMenu(context, ref, action, currentHost),
            itemBuilder: (context) => const <PopupMenuEntry<_ScreenMenuAction>>[
              PopupMenuItem<_ScreenMenuAction>(
                value: _ScreenMenuAction.projects,
                child: Text('Projects'),
              ),
              PopupMenuItem<_ScreenMenuAction>(
                value: _ScreenMenuAction.quotas,
                child: Text('Quotas'),
              ),
              PopupMenuItem<_ScreenMenuAction>(
                value: _ScreenMenuAction.settings,
                child: Text('Settings'),
              ),
              PopupMenuItem<_ScreenMenuAction>(
                value: _ScreenMenuAction.hostDetails,
                child: Text('Host Details'),
              ),
              PopupMenuItem<_ScreenMenuAction>(
                value: _ScreenMenuAction.renameHost,
                child: Text('Rename Host'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: switch ((data, prefs)) {
          (AsyncData(value: final listData), AsyncData())
              when listData.workspaces.isEmpty =>
            Column(
              children: <Widget>[
                _WorkspaceToolbar(hostId: host.id, data: listData),
                const Expanded(
                  child: AleraEmptyState(
                    title: 'No Workspaces',
                    message: 'Create A Workspace To Get Started.',
                    icon: AleraIcons.workspaces,
                  ),
                ),
              ],
            ),
          (
            AsyncData(value: final listData),
            AsyncData(value: final viewPrefs),
          ) =>
            _WorkspaceListBody(
              hostId: host.id,
              data: listData,
              prefs: viewPrefs,
            ),
          (AsyncError(:final error), _) => Column(
            children: <Widget>[
              _WorkspaceToolbar(hostId: host.id, data: data.value),
              Expanded(
                child: _ConnectionError(
                  error: error,
                  onRetry: () {
                    ref.invalidate(hostConnectionControllerProvider(host.id));
                  },
                ),
              ),
            ],
          ),
          _ => Column(
            children: <Widget>[
              _WorkspaceToolbar(hostId: host.id, data: data.value),
              const Expanded(child: Center(child: CircularProgressIndicator())),
            ],
          ),
        },
      ),
      floatingActionButton: data.value?.supportsMutations == true
          ? FloatingActionButton(
              tooltip: 'New Workspace',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<bool>(
                    builder: (_) => CreateWorkspaceScreen(
                      hostId: host.id,
                      projects: data.value!.projects,
                      workspaces: data.value!.workspaces,
                    ),
                  ),
                );
              },
              child: const Icon(AleraIcons.add),
            )
          : null,
    );
  }

  Future<void> _handleMenu(
    BuildContext context,
    WidgetRef ref,
    _ScreenMenuAction action,
    PairedHostProfile currentHost,
  ) async {
    switch (action) {
      case _ScreenMenuAction.hostDetails:
        if (context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => HostDashboardScreen(host: currentHost),
            ),
          );
        }
      case _ScreenMenuAction.projects:
        if (context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProjectsScreen(host: currentHost),
            ),
          );
        }
      case _ScreenMenuAction.quotas:
        if (context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => AgentQuotasScreen(host: currentHost),
            ),
          );
        }
      case _ScreenMenuAction.settings:
        if (context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => HostSettingsScreen(host: currentHost),
            ),
          );
        }
      case _ScreenMenuAction.renameHost:
        if (context.mounted) {
          await showRenameHostDialog(context, ref, currentHost);
        }
    }
  }
}

class _WorkspaceListBody extends ConsumerWidget {
  const _WorkspaceListBody({
    required this.hostId,
    required this.data,
    required this.prefs,
  });

  final String hostId;
  final WorkspaceListData data;
  final MobileViewPrefs prefs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expandedWorkspaceIds =
        ref.watch(workspaceAgentExpansionControllerProvider(hostId)).value ??
        const <String>{};
    final rows = buildMobileWorkspaceRows(
      workspaces: data.workspaces,
      projects: data.projects,
      prefs: prefs,
      activity: data.activity,
      agentPresence: data.agentPresence,
      searchQuery: ref.watch(workspaceSearchControllerProvider(hostId)),
    );
    final prefsController = ref.read(
      mobileViewPrefsControllerProvider(hostId).notifier,
    );
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(workspaceListControllerProvider(hostId));
        await ref.read(workspaceListControllerProvider(hostId).future);
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
            toolbarHeight: _WorkspaceToolbar.extent,
            titleSpacing: 0,
            centerTitle: false,
            title: SizedBox(
              width: double.infinity,
              child: _WorkspaceToolbar(hostId: hostId, data: data),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.only(bottom: AleraTokens.spaceXxl * 2),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final row = rows[index];
                return switch (row) {
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
                          workspaceAgentExpansionControllerProvider(
                            hostId,
                          ).notifier,
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

class _WorkspaceToolbar extends ConsumerWidget {
  const _WorkspaceToolbar({required this.hostId, required this.data});

  final String hostId;
  final WorkspaceListData? data;

  /// Dense search row plus vertical padding; drives [SliverAppBar.toolbarHeight].
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
                hintText: 'Search Workspaces',
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

class _ConnectionError extends StatelessWidget {
  const _ConnectionError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final updateRequired = error is UnsupportedError;
    return AleraEmptyState(
      title: updateRequired ? 'Update Required' : 'Connection Failed',
      message: error.toString(),
      icon: updateRequired ? AleraIcons.systemUpdate : AleraIcons.cloudOff,
      action: FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(AleraIcons.sync),
        label: const Text('Retry'),
      ),
    );
  }
}
