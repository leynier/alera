part of 'keyboard_command_dispatcher.dart';

/// Keyboard-only navigation between the surfaces a pointer would otherwise
/// click: panes, workspaces in the sidebar, and the context panel.
extension _KeyboardCommandDispatcherNavigation on KeyboardCommandDispatcher {
  /// Moves keyboard focus [delta] panes along the layout. When no pane holds
  /// the focus (it sits in the sidebar or a panel) the active pane is focused
  /// instead, so the same chord also brings the user back to the workbench.
  void _focusPane(int delta) {
    final state = ref.read(workbenchControllerProvider);
    final workspace = state.activeWorkspace;
    if (workspace == null) {
      return;
    }
    final registry = ref.read(workbenchPaneFocusRegistryProvider);
    final controller = ref.read(workbenchControllerProvider.notifier);
    final keys = _workspacePanelPaneKeys;
    if (keys.isEmpty) {
      return;
    }
    final panel = state.workspacePanelFor(workspace.id);
    final focused = registry.focusedKeyAmong(keys);
    if (focused != null && keys.length == 1) {
      // A single pane that already holds the focus: leave whatever descendant
      // has it (the composer, a toolbar field) alone.
      return;
    }
    final target = focused == null
        ? (keys.contains(panel.focusedKey) ? panel.focusedKey! : keys.first)
        : keys[_wrapIndex(keys.indexOf(focused) + delta, keys.length)];
    if (target == focused) {
      return;
    }
    controller.selectWorkspacePanelKey(workspace.id, target);
    _focusSurface(registry, target, workspace, state);
  }

  /// Focuses the active pane unless a pane already holds the focus. Used after
  /// an action collapsed the surface that held it, so typing does not land on
  /// the shortcut layer where it goes nowhere.
  void _focusActivePane() {
    final state = ref.read(workbenchControllerProvider);
    final workspace = state.activeWorkspace;
    if (workspace == null) {
      return;
    }
    final registry = ref.read(workbenchPaneFocusRegistryProvider);
    final keys = _workspacePanelNavigationKeys;
    final key = state.workspacePanelFor(workspace.id).focusedKey;
    if (key != null && registry.focusedKeyAmong(keys) == null) {
      _focusSurface(registry, key, workspace, state);
    }
  }

  void _focusSurface(
    WorkbenchPaneFocusRegistry registry,
    String key,
    Workspace workspace,
    WorkbenchState state,
  ) {
    final tabId = WorkspacePanel.tabId(key);
    final tab = tabId == null
        ? null
        : state.tabsFor(workspace.id).where((t) => t.id == tabId).firstOrNull;
    _focusContent(registry, key, tab);
  }

  /// A terminal is focused through its session handle, which reaches the
  /// emulator even when the pane scope has no focus history yet. Every other
  /// surface goes through the registered scope: its last focused descendant
  /// when there is one, otherwise the scope itself, whose focus change marks
  /// the pane active and lets the content claim focus on that transition.
  void _focusContent(
    WorkbenchPaneFocusRegistry registry,
    String key,
    WorkspaceTabRecord? tab,
  ) {
    if (tab != null && tab.kind == WorkspaceTabKind.terminal) {
      final session = ref.read(terminalRuntimeProvider).peekSession(tab.id);
      if (session != null) {
        session.requestFocus();
        return;
      }
    }
    registry.focus(key);
  }

  /// Selects the workspace [delta] rows away in the sidebar's rendered order,
  /// honoring its filters, sections and search like a click would.
  void _cycleWorkspace(int delta) {
    final state = ref.read(workbenchControllerProvider);
    final rows = ref.read(workbenchSidebarRowsProvider);
    final order = <WorkbenchWorkspaceRow>[
      for (final row in rows)
        if (row is WorkbenchWorkspaceRow && !row.isPinnedCopy) row,
    ];
    if (order.isEmpty) {
      return;
    }
    final activeId = state.activeWorkspaceId;
    final currentIndex = order.indexWhere(
      (row) => row.workspace.id == activeId,
    );
    final target = currentIndex < 0
        ? (delta > 0 ? order.first : order.last)
        : order[_wrapIndex(currentIndex + delta, order.length)];
    if (target.workspace.id == activeId) {
      return;
    }
    unawaited(
      ref
          .read(workbenchControllerProvider.notifier)
          .selectWorkspace(
            project: target.project,
            workspace: target.workspace,
          ),
    );
  }

  /// Shows the Search panel and asks it to focus the query, or to show and
  /// focus the replacement field, even when the panel is already open.
  void _revealWorkspaceSearch({required bool replace}) {
    if (ref.read(workbenchControllerProvider).activeWorkspace == null) {
      return;
    }
    _showContextPanel(.search);
    ref.read(workspaceSearchRevealProvider.notifier).request(replace: replace);
  }

  void _toggleContextPanel() {
    final state = ref.read(workbenchControllerProvider);
    if (state.activeWorkspace == null) {
      return;
    }
    final controller = ref.read(workbenchControllerProvider.notifier);
    final visible = state.viewPrefs.rightSidebarVisible;
    controller.setRightSidebarVisible(!visible);
    if (visible) {
      // The panel that held the focus is gone; land in the workbench rather
      // than on the shortcut layer, where typing goes nowhere.
      _focusActivePane();
    }
  }

  int _wrapIndex(int index, int length) {
    final wrapped = index % length;
    return wrapped < 0 ? wrapped + length : wrapped;
  }
}
