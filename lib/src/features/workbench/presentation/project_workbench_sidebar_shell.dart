part of 'project_workbench_sidebar.dart';

class ProjectWorkbenchSidebar extends ConsumerStatefulWidget {
  const ProjectWorkbenchSidebar({super.key});

  @override
  ConsumerState<ProjectWorkbenchSidebar> createState() =>
      _ProjectWorkbenchSidebarState();
}

class _ProjectWorkbenchSidebarState
    extends ConsumerState<ProjectWorkbenchSidebar>
    with _WorkspaceSidebarActions, _ProjectWorkbenchSidebarActions {
  final FocusNode _searchFocus = FocusNode();
  double? _transientSidebarWidth;

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sidebar = ref.watch(
      workbenchControllerProvider.select(
        (state) => (
          activeProjectId: state.activeProjectId,
          activeTabIdByWorkspace: state.activeTabIdByWorkspace,
          activeWorkspaceId: state.activeWorkspaceId,
          collapsed: state.collapsed,
          projects: state.projects,
          searchQuery: state.searchQuery,
          tabsByWorkspace: state.tabsByWorkspace,
          viewPrefs: state.viewPrefs,
          workspacesByProject: state.workspacesByProject,
        ),
      ),
    );
    final state = WorkbenchState(
      projects: sidebar.projects,
      workspacesByProject: sidebar.workspacesByProject,
      tabsByWorkspace: sidebar.tabsByWorkspace,
      viewPrefs: sidebar.viewPrefs,
      activeProjectId: sidebar.activeProjectId,
      activeWorkspaceId: sidebar.activeWorkspaceId,
      activeTabIdByWorkspace: sidebar.activeTabIdByWorkspace,
      searchQuery: sidebar.searchQuery,
      collapsed: sidebar.collapsed,
    );
    final controller = ref.read(workbenchControllerProvider.notifier);
    final workspaceFolderOpener = ref.read(workspaceFolderOpenerProvider);
    if (state.collapsed) {
      return _CollapsedSidebar(
        state: state,
        controller: controller,
        onAddProject: _addProject,
        onOpenSettings: () => unawaited(_openSettings()),
      );
    }
    final sidebarWidth = _transientSidebarWidth ?? state.viewPrefs.sidebarWidth;
    return SizedBox(
      width: sidebarWidth,
      child: Stack(
        children: <Widget>[
          Container(
            decoration: const BoxDecoration(
              color: AleraTokens.surfaceVariant,
              border: Border(
                right: BorderSide(color: AleraTokens.borderSubtle),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SidebarBrandRow(
                  collapsed: false,
                  onToggleCollapsed: () =>
                      controller.setCollapsed(!state.collapsed),
                ),
                const Divider(height: 1, color: AleraTokens.borderSubtle),
                SidebarSearchBar(
                  initialQuery: state.searchQuery,
                  focusNode: _searchFocus,
                  onChanged: controller.setSearchQuery,
                  hintText: 'Search workspaces',
                ),
                WorkbenchSidebarToolbar(
                  onAddWorkspace: _createWorkspaceForActiveProject,
                ),
                const Divider(height: 1, color: AleraTokens.borderSubtle),
                Expanded(
                  // One ticker for every agent spinner in the list.
                  child: AgentRunSpinnerScope(
                    child: state.projects.isEmpty
                        ? _EmptyProjectsView(onAddProject: _addProject)
                        : Consumer(
                            builder: (context, ref, _) {
                              // The rows are memoized in a provider, so this only
                              // rebuilds when the computed list actually changes.
                              final rows = ref.watch(
                                workbenchSidebarRowsProvider,
                              );
                              return _SidebarBody(
                                state: state,
                                controller: controller,
                                rows: rows,
                                onOpenWorkspace: _openWorkspace,
                                onOpenWorkspaceFolder: openWorkspaceFolder,
                                onCopyWorkspacePath: copyWorkspacePath,
                                onOpenWorkspaceInBrowser:
                                    openWorkspaceInBrowser,
                                onSleepWorkspace: sleepWorkspace,
                                onCreateWorkspace: _createWorkspace,
                                onDeleteWorkspace: _deleteWorkspace,
                                onRenameProject: _renameProject,
                                onRemoveProject: _removeProject,
                                onRenameWorkspace: _renameWorkspace,
                                onSetWorkspacePinned: _setWorkspacePinned,
                                onManageWorkspaceTags: _manageWorkspaceTags,
                                onSetWorkspaceParent: _setWorkspaceParent,
                                onClearWorkspaceParent: _clearWorkspaceParent,
                                fileManagerLabel:
                                    workspaceFolderOpener.fileManagerLabel,
                                onSelectTerminal: _selectTerminal,
                                onCloseTerminal: _closeTerminal,
                              );
                            },
                          ),
                  ),
                ),
                const Divider(height: 1, color: AleraTokens.borderSubtle),
                _SidebarFooter(
                  onAddProject: _addProject,
                  onOpenSettings: () => unawaited(_openSettings()),
                ),
              ],
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: SidebarResizeHandle(
              currentWidth: sidebarWidth,
              onResize: (width) {
                setState(() {
                  _transientSidebarWidth = width.clamp(
                    AleraTokens.sidebarMinWidth,
                    AleraTokens.sidebarMaxWidth,
                  );
                });
              },
              onResizeEnd: (width) {
                controller.setSidebarWidth(width);
                setState(() => _transientSidebarWidth = null);
              },
            ),
          ),
        ],
      ),
    );
  }
}
