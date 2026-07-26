import 'dart:async';

import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/surfaces/alera_hover_card.dart';
import 'package:alera/src/features/resource_manager/application/resource_manager_providers.dart';
import 'package:alera/src/features/resource_manager/domain/resource_snapshot.dart';
import 'package:alera/src/features/resource_manager/domain/resource_tree.dart';
import 'package:alera/src/features/resource_manager/presentation/resource_status_chip.dart';
import 'package:alera/src/features/resource_manager/presentation/resource_status_panel.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Status-bar entry point for the resource manager: a chip that opens the
/// panel in an overlay anchored above it.
class ResourceStatusBarControl extends ConsumerStatefulWidget {
  const ResourceStatusBarControl({super.key});

  @override
  ConsumerState<ResourceStatusBarControl> createState() =>
      _ResourceStatusBarControlState();
}

class _ResourceStatusBarControlState
    extends ConsumerState<ResourceStatusBarControl> {
  final AleraHoverCardController _hoverCard = AleraHoverCardController();
  ResourceSortColumn _sortColumn = ResourceSortColumn.memory;
  final Set<String> _collapsedProjectIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final snapshot =
        ref.watch(resourceSnapshotProvider).value ??
        ResourceSnapshot.unavailable();
    final tree = ref.watch(resourceTreeProvider(_sortColumn));
    final sessionCount = tree.projects.fold<int>(
      0,
      (total, project) =>
          total +
          project.workspaces.fold<int>(
            0,
            (subtotal, workspace) => subtotal + workspace.sessions.length,
          ),
    );

    return AleraHoverCard(
      controller: _hoverCard,
      // The chip runs its own InkWell, which would win the gesture arena over
      // the card's detector, so the chip drives pinning through the controller.
      pinOnTap: false,
      semanticsLabel: 'Resource Manager',
      onVisibilityChanged: _handleVisibilityChanged,
      card: ResourceStatusPanel(
        snapshot: snapshot,
        tree: tree,
        sortColumn: _sortColumn,
        hostUnreachable: snapshot.error != null,
        collapsedProjectIds: _collapsedProjectIds,
        onSortColumnChanged: (column) => setState(() => _sortColumn = column),
        onToggleProject: (projectId) => setState(() {
          if (!_collapsedProjectIds.remove(projectId)) {
            _collapsedProjectIds.add(projectId);
          }
        }),
        onOpenSession: _openSession,
        onKillSession: (session) => unawaited(_killSession(session)),
        onKillOrphans: () => unawaited(_killOrphans(tree.orphanSessions)),
      ),
      child: ResourceStatusChip(
        snapshot: snapshot,
        sessionCount: sessionCount,
        orphanCount: tree.orphanSessions.length,
        onPressed: _hoverCard.togglePin,
      ),
    );
  }

  void _handleVisibilityChanged(bool visible) {
    ref.read(resourcePanelOpenProvider.notifier).set(open: visible);
    if (visible) {
      // Showing switches the poll to the host's own 2 s cadence, and also keeps
      // the host's sampler alive while the panel is on screen.
      ref.invalidate(resourceSnapshotProvider);
    }
  }

  void _openSession(ResourceSessionRow session) {
    final controller = ref.read(workbenchControllerProvider.notifier);
    final state = ref.read(workbenchControllerProvider);
    final workspace = _workspaceForTab(session.tabId);
    if (workspace == null) {
      return;
    }
    final project = state.projects
        .where((candidate) => candidate.id == workspace.projectId)
        .firstOrNull;
    if (project == null) {
      return;
    }
    _hoverCard.dismiss();
    unawaited(() async {
      await controller.selectWorkspace(project: project, workspace: workspace);
      controller.setActiveTab(workspaceId: workspace.id, tabId: session.tabId);
    }());
  }

  /// Killing a session with a tab closes the tab, which is the flow the user
  /// already knows. An orphan has no pane to lose, so it is terminated
  /// directly and without a prompt.
  Future<void> _killSession(ResourceSessionRow session) async {
    if (session.orphan) {
      await ref.read(runtimeHostClientProvider).terminate(session.sessionId);
      ref.invalidate(resourceSnapshotProvider);
      return;
    }
    final workspace = _workspaceForTab(session.tabId);
    if (workspace == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Close Terminal Session',
        message:
            'Force-quits ${session.label}. Anything running in that terminal '
            'is lost.',
        confirmLabel: 'Close',
        destructive: true,
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref
        .read(workbenchControllerProvider.notifier)
        .closeWorkspaceTab(workspace: workspace, tabId: session.tabId);
    ref.invalidate(resourceSnapshotProvider);
  }

  Future<void> _killOrphans(List<ResourceSessionRow> orphans) async {
    final client = ref.read(runtimeHostClientProvider);
    await Future.wait(<Future<void>>[
      for (final orphan in orphans) client.terminate(orphan.sessionId),
    ]);
    ref.invalidate(resourceSnapshotProvider);
  }

  Workspace? _workspaceForTab(String tabId) {
    final state = ref.read(workbenchControllerProvider);
    for (final entry in state.tabsByWorkspace.entries) {
      if (entry.value.any((tab) => tab.id == tabId)) {
        for (final workspaces in state.workspacesByProject.values) {
          for (final workspace in workspaces) {
            if (workspace.id == entry.key) {
              return workspace;
            }
          }
        }
      }
    }
    return null;
  }
}
