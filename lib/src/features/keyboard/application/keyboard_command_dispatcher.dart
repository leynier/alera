import 'dart:async';

import 'package:alera/src/features/app_menu/presentation/app_menu_actions.dart';
import 'package:alera/src/features/orchestration/application/run_board_navigation.dart';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/keyboard/presentation/keyboard_command_palette_dialog.dart';
import 'package:alera/src/features/workbench/application/workbench_listing.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workspace_search_reveal.dart';
import 'package:alera/src/features/workbench/domain/workspace_panel.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:alera/src/features/workbench/presentation/workbench_hand_off_launchers.dart';
import 'package:alera/src/features/workbench/presentation/workbench_pane_focus_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'keyboard_command_dispatcher_navigation.dart';

/// Maps a [KeyboardActionId] to concrete app behavior, reusing existing
/// controller methods and dialog flows. Construct one per dispatch with the
/// current [ref] and a [context] suitable for showing dialogs/toasts.
class const KeyboardCommandDispatcher({
  required final WidgetRef ref,
  required final BuildContext context,
  final TerminalSessionHandle? terminalSession,
}) {
  /// Restore the active workbench pane after a global surface was dismissed.
  void focusActivePane() => _focusActivePane();

  void dispatch(KeyboardActionId id) {
    if (ref.read(runBoardNavigationProvider).visible &&
        keybindingDefinitions.firstWhere((action) => action.id == id).group !=
            KeyboardActionGroup.global) {
      return;
    }
    switch (id) {
      case KeyboardActionId.openRunBoard:
        openRunBoardFromAppMenu(ref);
      case KeyboardActionId.openSettings:
        unawaited(openSettingsDialog(context));
      case KeyboardActionId.openAutomations:
        unawaited(openAutomationsDialog(context));
      case KeyboardActionId.openQuickOpen:
        unawaited(showQuickOpenFlow(context, ref));
      case KeyboardActionId.openCommandPalette:
        unawaited(
          showKeyboardCommandPalette(
            context,
            onExecute: (command) => dispatch(command),
          ),
        );
      case KeyboardActionId.addProject:
        unawaited(showAddProjectFlow(context, ref));
      case KeyboardActionId.toggleSidebar:
        _toggleSidebar();
      case KeyboardActionId.toggleContextPanel:
        _toggleContextPanel();
      case KeyboardActionId.showExplorer:
        _showContextPanel(.explorer);
      case KeyboardActionId.showSourceControl:
        _showContextPanel(.gitDiff);
      case KeyboardActionId.createWorkspace:
        final project = ref.read(workbenchControllerProvider).activeProject;
        unawaited(
          showCreateWorkspaceFlow(context, ref, initialProject: project),
        );
      case KeyboardActionId.handOffWorkspace:
        unawaited(_handOffActiveWorkspace());
      case KeyboardActionId.handOnWorkspace:
        unawaited(_handOnActiveWorkspace());
      case KeyboardActionId.navigateBack:
        unawaited(ref.read(workbenchControllerProvider.notifier).goBack());
      case KeyboardActionId.navigateForward:
        unawaited(ref.read(workbenchControllerProvider.notifier).goForward());
      case KeyboardActionId.previousWorkspace:
        _cycleWorkspace(-1);
      case KeyboardActionId.nextWorkspace:
        _cycleWorkspace(1);
      case KeyboardActionId.findInFiles:
        _revealWorkspaceSearch(replace: false);
      case KeyboardActionId.findInTerminal:
        _openTerminalSearch();
      case KeyboardActionId.toggleTerminalComposer:
        _toggleTerminalComposer();
      case KeyboardActionId.replaceInFiles:
        _revealWorkspaceSearch(replace: true);
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
        _split(.right);
      case KeyboardActionId.splitDown:
        _split(.down);
      case KeyboardActionId.closeSplit:
        _closeSplit();
      case KeyboardActionId.focusNextPane:
        _focusPane(1);
      case KeyboardActionId.focusPreviousPane:
        _focusPane(-1);
    }
  }

  Future<void> _handOffActiveWorkspace() async {
    final workspace = ref.read(workbenchControllerProvider).activeWorkspace;
    if (workspace == null || !workspace.isMain) {
      return;
    }
    await showHandOffWorkspaceFlow(context, ref, workspace: workspace);
  }

  Future<void> _handOnActiveWorkspace() async {
    final state = ref.read(workbenchControllerProvider);
    final workspace = state.activeWorkspace;
    final project = state.activeProject;
    if (workspace == null || project == null || workspace.isMain) {
      return;
    }
    await showHandOnWorkspaceFlow(
      context,
      ref,
      project: project,
      workspace: workspace,
    );
  }

  void _toggleSidebar() {
    final controller = ref.read(workbenchControllerProvider.notifier);
    final collapsed = ref.read(workbenchControllerProvider).collapsed;
    controller.setCollapsed(!collapsed);
    if (!collapsed) {
      // Collapsing the sidebar that held the focus (its search field, a row
      // menu) must not park the keyboard on the shortcut layer.
      _focusActivePane();
    }
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

  void _openTerminalSearch() {
    final directSession = terminalSession;
    if (directSession != null) {
      directSession.openSearch();
      return;
    }
    final state = ref.read(workbenchControllerProvider);
    final tab = state.activeWorkspaceTab;
    if (tab == null || tab.kind != WorkspaceTabKind.terminal) {
      return;
    }
    ref.read(terminalRuntimeProvider).peekSession(tab.id)?.openSearch();
  }

  void _toggleTerminalComposer() {
    final directSession = terminalSession;
    if (directSession != null) {
      directSession.composerController.toggle();
      return;
    }
    final tab = ref.read(workbenchControllerProvider).activeWorkspaceTab;
    if (tab == null || tab.kind != WorkspaceTabKind.terminal) {
      return;
    }
    ref
        .read(terminalRuntimeProvider)
        .peekSession(tab.id)
        ?.composerController
        .toggle();
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
    if (workspace != null) {
      final tool = WorkspaceTool.forKey(
        state.workspacePanelFor(workspace.id).focusedKey,
      );
      if (tool != null) {
        ref
            .read(workbenchControllerProvider.notifier)
            .closeWorkspaceTool(workspace.id, tool);
        return;
      }
    }
    if (workspace == null) {
      return;
    }
    final focusedTabId = WorkspacePanel.tabId(
      state.workspacePanelFor(workspace.id).focusedKey,
    );
    final tab = focusedTabId == null
        ? state.activeWorkspaceTab
        : state
                  .tabsFor(workspace.id)
                  .where((candidate) => candidate.id == focusedTabId)
                  .firstOrNull ??
              state.activeWorkspaceTab;
    if (tab == null) {
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
      if (!context.mounted) return;
      // The controller disposes the terminal handle and editor document.
      await ref
          .read(workbenchControllerProvider.notifier)
          .closeWorkspaceTab(workspace: workspace, tabId: tab.id);
    }());
  }

  void _cycleTab(int delta) {
    final keys = _focusedPaneTabKeys;
    if (keys.length < 2) {
      return;
    }
    final currentKey = _focusedPaneKey;
    final index = keys.indexOf(currentKey ?? '');
    final base = index < 0 ? 0 : index;
    _goToTabIndex(_wrapIndex(base + delta, keys.length));
  }

  void _goToTabIndex(int index) {
    final state = ref.read(workbenchControllerProvider);
    final workspaceId = state.activeWorkspaceId;
    if (workspaceId == null) {
      return;
    }
    final keys = _focusedPaneTabKeys;
    if (index >= 0 && index < keys.length) {
      ref
          .read(workbenchControllerProvider.notifier)
          .selectWorkspacePanelKey(workspaceId, keys[index]);
    }
  }

  void _goToLastTab() {
    final keys = _focusedPaneTabKeys;
    if (keys.isEmpty) {
      return;
    }
    _goToTabIndex(keys.length - 1);
  }

  void _split(WorkbenchDropZone zone) {
    final state = ref.read(workbenchControllerProvider);
    final workspace = state.activeWorkspace;
    if (workspace == null) {
      return;
    }
    final controller = ref.read(workbenchControllerProvider.notifier);
    final runtime = ref.read(terminalRuntimeProvider);
    final panel = state.workspacePanelFor(workspace.id);
    final tree =
        panel.treeForKey(panel.focusedKey ?? '') ?? WorkspacePanelTree.right;
    final layout = tree == WorkspacePanelTree.main
        ? panel.ensuredMainLayout(workspace.id)
        : panel.ensuredLayout(workspace.id);
    final groupId = layout.activeGroupId;
    unawaited(() async {
      final tab = await controller.splitWorkbenchGroupWithTerminal(
        workspace: workspace,
        groupId: groupId,
        zone: zone,
      );
      runtime.sessionFor(workspace: workspace, tab: tab).requestFocus();
    }());
  }

  void _closeSplit() {
    final state = ref.read(workbenchControllerProvider);
    final workspace = state.activeWorkspace;
    if (workspace == null) {
      return;
    }
    final panel = state.workspacePanelFor(workspace.id);
    final tree =
        panel.treeForKey(panel.focusedKey ?? '') ?? WorkspacePanelTree.right;
    final layout = tree == WorkspacePanelTree.main
        ? panel.ensuredMainLayout(workspace.id)
        : panel.ensuredLayout(workspace.id);
    if (layout.groups.length < 2) {
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

  List<String> get _workspacePanelNavigationKeys {
    final state = ref.read(workbenchControllerProvider);
    final id = state.activeWorkspaceId;
    if (id == null) return const <String>[];
    final panel = state.workspacePanelFor(id);
    return <String>[
      ...panel.mainKeys,
      for (final key in panel.tabKeys)
        if (!panel.mainKeys.contains(key)) key,
    ];
  }

  /// Active tab of each visible pane, main column then right sidebar, so
  /// Focus Next/Previous Pane moves between columns rather than tabs.
  List<String> get _workspacePanelPaneKeys {
    final state = ref.read(workbenchControllerProvider);
    final id = state.activeWorkspaceId;
    if (id == null) {
      return const <String>[];
    }
    final panel = state.workspacePanelFor(id);
    final seen = <String>{};
    final keys = <String>[];
    void addFrom(WorkbenchLayout layout) {
      for (final groupId in layout.paneGroupIds) {
        final key = layout.groups[groupId]?.activeTabId;
        if (key == null || !seen.add(key)) {
          continue;
        }
        keys.add(key);
      }
    }

    addFrom(panel.ensuredMainLayout(id));
    addFrom(panel.ensuredLayout(id));
    return keys;
  }

  String? get _focusedPaneKey {
    final state = ref.read(workbenchControllerProvider);
    final workspaceId = state.activeWorkspaceId;
    if (workspaceId == null) {
      return null;
    }
    final panel = state.workspacePanelFor(workspaceId);
    return panel.focusedKey ??
        (state.activeWorkspaceTab == null
            ? null
            : WorkspacePanel.tabKey(state.activeWorkspaceTab!.id));
  }

  List<String> get _focusedPaneTabKeys {
    final state = ref.read(workbenchControllerProvider);
    final workspaceId = state.activeWorkspaceId;
    if (workspaceId == null) {
      return const <String>[];
    }
    final panel = state.workspacePanelFor(workspaceId);
    final key = _focusedPaneKey;
    if (key != null) {
      final main = panel.ensuredMainLayout(workspaceId);
      final mainGroupId = main.groupIdForTab(key);
      if (mainGroupId != null) {
        return main.groups[mainGroupId]?.tabIds ?? const <String>[];
      }
      final right = panel.ensuredLayout(workspaceId);
      final rightGroupId = right.groupIdForTab(key);
      if (rightGroupId != null) {
        return right.groups[rightGroupId]?.tabIds ?? const <String>[];
      }
    }
    return panel.ensuredMainLayout(workspaceId).activeGroup?.tabIds ??
        panel.ensuredLayout(workspaceId).activeGroup?.tabIds ??
        const <String>[];
  }
}
