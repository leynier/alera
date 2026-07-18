import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/hosts/presentation/rename_host_dialog.dart';
import 'package:alera_mobile/src/features/runtime/application/host_connection_controller.dart';
import 'package:alera_mobile/src/features/runtime/presentation/host_dashboard_screen.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_view_prefs_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_workspace_rows.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';
import 'package:alera_mobile/src/features/workbench/presentation/create_workspace_screen.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_actions_sheet.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_row_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _ScreenMenuAction { groupByProject, hostDetails, renameHost }

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
    final currentHost =
        ref
            .watch(pairedHostsControllerProvider)
            .value
            ?.where((profile) => profile.id == host.id)
            .firstOrNull ??
        host;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: <Widget>[
            _ConnectionDot(connected: connection.hasValue),
            const SizedBox(width: AleraTokens.spaceSm),
            Expanded(
              child: Text(
                currentHost.effectiveName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          PopupMenuButton<_ScreenMenuAction>(
            onSelected: (action) =>
                _handleMenu(context, ref, action, currentHost, prefs.value),
            itemBuilder: (context) => <PopupMenuEntry<_ScreenMenuAction>>[
              CheckedPopupMenuItem<_ScreenMenuAction>(
                value: _ScreenMenuAction.groupByProject,
                checked: prefs.value?.groupBy == MobileWorkspaceGroupBy.project,
                child: const Text('Group By Project'),
              ),
              const PopupMenuItem<_ScreenMenuAction>(
                value: _ScreenMenuAction.hostDetails,
                child: Text('Host Details'),
              ),
              const PopupMenuItem<_ScreenMenuAction>(
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
            const _EmptyWorkspaces(),
          (
            AsyncData(value: final listData),
            AsyncData(value: final viewPrefs),
          ) =>
            _WorkspaceListBody(
              hostId: host.id,
              data: listData,
              prefs: viewPrefs,
            ),
          (AsyncError(:final error), _) => _ConnectionError(
            error: error,
            onRetry: () {
              ref.invalidate(hostConnectionControllerProvider(host.id));
            },
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
      floatingActionButton: data.value?.supportsMutations == true
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<bool>(
                    builder: (_) => CreateWorkspaceScreen(
                      hostId: host.id,
                      projects: data.value!.projects,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('New Workspace'),
            )
          : null,
    );
  }

  Future<void> _handleMenu(
    BuildContext context,
    WidgetRef ref,
    _ScreenMenuAction action,
    PairedHostProfile currentHost,
    MobileViewPrefs? prefs,
  ) async {
    switch (action) {
      case _ScreenMenuAction.groupByProject:
        await ref
            .read(mobileViewPrefsControllerProvider(host.id).notifier)
            .setGroupBy(
              prefs?.groupBy == MobileWorkspaceGroupBy.project
                  ? MobileWorkspaceGroupBy.none
                  : MobileWorkspaceGroupBy.project,
            );
      case _ScreenMenuAction.hostDetails:
        if (context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => HostDashboardScreen(host: currentHost),
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
    final rows = buildMobileWorkspaceRows(
      workspaces: data.workspaces,
      projects: data.projects,
      prefs: prefs,
    );
    final prefsController = ref.read(
      mobileViewPrefsControllerProvider(hostId).notifier,
    );
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AleraTokens.spaceXxl * 2),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return switch (row) {
          MobilePinnedHeaderRow(:final count, :final collapsed) =>
            MobileSectionHeader(
              label: 'Pinned',
              icon: Icons.push_pin,
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
              icon: Icons.folder_outlined,
              count: count,
              collapsed: collapsed,
              onToggle: () => prefsController.toggleProjectCollapsed(projectId),
            ),
          MobileWorkspaceEntryRow() => MobileWorkspaceListRow(
            row: row,
            onTap: () => showWorkspaceActionsSheet(
              context,
              ref,
              hostId: hostId,
              workspace: row.entry.workspace,
              data: data,
            ),
            onLongPress: () => showWorkspaceActionsSheet(
              context,
              ref,
              hostId: hostId,
              workspace: row.entry.workspace,
              data: data,
            ),
            onToggleChildren: () =>
                prefsController.toggleParentCollapsed(row.entry.workspace.id),
          ),
        };
      },
    );
  }
}

class _ConnectionDot extends StatelessWidget {
  const _ConnectionDot({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AleraTokens.spaceSm,
      height: AleraTokens.spaceSm,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: connected ? AleraTokens.success : AleraTokens.foregroundMuted,
      ),
    );
  }
}

class _EmptyWorkspaces extends StatelessWidget {
  const _EmptyWorkspaces();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.workspaces_outline,
              size: AleraTokens.emptyIcon,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AleraTokens.spaceLg),
            Text(
              'No Workspaces',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AleraTokens.spaceSm),
            Text(
              'Create A Workspace To Get Started.',
              style: Theme.of(context).textTheme.bodyMedium,
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
    return Center(
      child: Padding(
        padding: AleraTokens.contentPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.cloud_off_outlined,
              size: AleraTokens.emptyIcon,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: AleraTokens.spaceLg),
            Text(
              'Connection Failed',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AleraTokens.spaceSm),
            Text(
              error.toString(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AleraTokens.spaceLg),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
