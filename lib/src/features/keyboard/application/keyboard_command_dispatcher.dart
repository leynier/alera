import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Maps a [KeyboardActionId] to concrete app behavior, reusing existing
/// controller methods and dialog flows. Construct one per dispatch with the
/// current [ref] and a [context] suitable for showing dialogs/toasts.
class KeyboardCommandDispatcher {
  const KeyboardCommandDispatcher({required this.ref, required this.context});

  final WidgetRef ref;
  final BuildContext context;

  void dispatch(KeyboardActionId id) {
    switch (id) {
      case KeyboardActionId.openSettings:
        unawaited(openSettingsDialog(context));
      case KeyboardActionId.addProject:
        unawaited(showAddProjectFlow(context, ref));
      case KeyboardActionId.toggleSidebar:
        _toggleSidebar();
      case KeyboardActionId.createWorkspace:
        final project = ref.read(workbenchControllerProvider).activeProject;
        unawaited(
          showCreateWorkspaceFlow(context, ref, initialProject: project),
        );
      case KeyboardActionId.findInFiles:
        _showContextPanel(WorkbenchContextPanelTab.search);
      case KeyboardActionId.replaceInFiles:
        _showContextPanel(WorkbenchContextPanelTab.search);
      case KeyboardActionId.saveFile:
        _saveActiveEditor();
      case KeyboardActionId.newTerminalTab:
        _newTerminalTab();
      case KeyboardActionId.closeTab:
        _closeActiveTab();
      case KeyboardActionId.nextTab:
        _cycleTab(1);
      case KeyboardActionId.previousTab:
        _cycleTab(-1);
      case KeyboardActionId.goToTab1:
      case KeyboardActionId.goToTab2:
      case KeyboardActionId.goToTab3:
      case KeyboardActionId.goToTab4:
      case KeyboardActionId.goToTab5:
      case KeyboardActionId.goToTab6:
      case KeyboardActionId.goToTab7:
      case KeyboardActionId.goToTab8:
        _goToTabIndex(id.tabIndex! - 1);
      case KeyboardActionId.goToTab9:
        _goToLastTab();
      case KeyboardActionId.splitRight:
        _split(WorkbenchDropZone.right);
      case KeyboardActionId.splitDown:
        _split(WorkbenchDropZone.down);
      case KeyboardActionId.closeSplit:
        _closeSplit();
    }
  }

  void _toggleSidebar() {
    final controller = ref.read(workbenchControllerProvider.notifier);
    final collapsed = ref.read(workbenchControllerProvider).collapsed;
    controller.setCollapsed(!collapsed);
  }

  void _newTerminalTab() {
    final workspace = ref.read(workbenchControllerProvider).activeWorkspace;
    if (workspace == null) {
      return;
    }
    final controller = ref.read(workbenchControllerProvider.notifier);
    final runtime = ref.read(terminalRuntimeProvider);
    unawaited(() async {
      final tab = await controller.createTerminalTab(workspace);
      runtime.sessionFor(workspace: workspace, tab: tab).requestFocus();
    }());
  }

  void _showContextPanel(WorkbenchContextPanelTab tab) {
    final state = ref.read(workbenchControllerProvider);
    if (state.activeWorkspace == null) {
      return;
    }
    final controller = ref.read(workbenchControllerProvider.notifier);
    controller.setContextPanelTab(tab);
    controller.setRightSidebarVisible(true);
  }

  void _saveActiveEditor() {
    final tab = ref.read(workbenchControllerProvider).activeWorkspaceTab;
    if (tab == null || tab.kind != WorkspaceTabKind.editor) {
      return;
    }
    unawaited(ref.read(editorSessionRegistryProvider).save(tab.id));
  }

  void _closeActiveTab() {
    final state = ref.read(workbenchControllerProvider);
    final workspace = state.activeWorkspace;
    final tab = state.activeWorkspaceTab;
    if (workspace == null || tab == null) {
      return;
    }
    unawaited(() async {
      final registry = ref.read(editorSessionRegistryProvider);
      if (registry.isDirty(tab.id)) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AleraConfirmDialog(
            title: 'Close unsaved editor?',
            message: '${tab.title} has unsaved changes.',
            confirmLabel: 'Close',
            destructive: true,
          ),
        );
        if (confirmed != true) {
          return;
        }
      }
      ref.read(terminalRuntimeProvider).closeTab(tab.id);
      await ref
          .read(workbenchControllerProvider.notifier)
          .closeWorkspaceTab(workspace: workspace, tabId: tab.id);
      registry.forget(tab.id);
    }());
  }

  void _cycleTab(int delta) {
    final state = ref.read(workbenchControllerProvider);
    final layout = state.activeLayout;
    final workspace = state.activeWorkspace;
    final group = layout?.activeGroup;
    if (layout == null || workspace == null || group == null) {
      return;
    }
    final tabIds = group.tabIds;
    if (tabIds.length < 2) {
      return;
    }
    final current = group.activeTabId;
    final currentIndex = current == null ? 0 : tabIds.indexOf(current);
    final base = currentIndex < 0 ? 0 : currentIndex;
    final nextIndex = (base + delta) % tabIds.length;
    final wrapped = nextIndex < 0 ? nextIndex + tabIds.length : nextIndex;
    ref
        .read(workbenchControllerProvider.notifier)
        .setActiveWorkspaceTab(
          workspaceId: workspace.id,
          groupId: layout.activeGroupId,
          tabId: tabIds[wrapped],
        );
  }

  void _goToTabIndex(int index) {
    final state = ref.read(workbenchControllerProvider);
    final layout = state.activeLayout;
    final workspace = state.activeWorkspace;
    final group = layout?.activeGroup;
    if (layout == null || workspace == null || group == null) {
      return;
    }
    if (index < 0 || index >= group.tabIds.length) {
      return;
    }
    ref
        .read(workbenchControllerProvider.notifier)
        .setActiveWorkspaceTab(
          workspaceId: workspace.id,
          groupId: layout.activeGroupId,
          tabId: group.tabIds[index],
        );
  }

  void _goToLastTab() {
    final group = ref
        .read(workbenchControllerProvider)
        .activeLayout
        ?.activeGroup;
    if (group == null || group.tabIds.isEmpty) {
      return;
    }
    _goToTabIndex(group.tabIds.length - 1);
  }

  void _split(WorkbenchDropZone zone) {
    final state = ref.read(workbenchControllerProvider);
    final workspace = state.activeWorkspace;
    final layout = state.activeLayout;
    if (workspace == null || layout == null) {
      return;
    }
    final controller = ref.read(workbenchControllerProvider.notifier);
    final runtime = ref.read(terminalRuntimeProvider);
    unawaited(() async {
      final tab = await controller.splitWorkbenchGroupWithTerminal(
        workspace: workspace,
        groupId: layout.activeGroupId,
        zone: zone,
      );
      runtime.sessionFor(workspace: workspace, tab: tab).requestFocus();
    }());
  }

  void _closeSplit() {
    final state = ref.read(workbenchControllerProvider);
    final workspace = state.activeWorkspace;
    final layout = state.activeLayout;
    if (workspace == null || layout == null || layout.groups.length < 2) {
      return;
    }
    unawaited(
      ref
          .read(workbenchControllerProvider.notifier)
          .mergeWorkbenchGroupIntoSibling(
            workspaceId: workspace.id,
            groupId: layout.activeGroupId,
          ),
    );
  }
}
