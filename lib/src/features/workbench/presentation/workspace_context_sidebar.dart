import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_canvas/presentation/agent_canvas_panel.dart';
import 'package:alera/src/features/pull_requests/presentation/workspace_pull_requests_panel.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_source_control_scope.dart';
import 'package:alera/src/features/workbench/presentation/workspace_explorer.dart';
import 'package:alera/src/features/workbench/presentation/workspace_git_diff_panel.dart';
import 'package:alera/src/features/workbench/presentation/workspace_search_panel.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter/material.dart';

class WorkspaceContextSidebar extends StatelessWidget {
  const WorkspaceContextSidebar({
    super.key,
    required this.workspace,
    required this.prefs,
    this.sourceControlScope,
    this.sourceControlAvailable = true,
    this.focusedSourceControlRoot,
    required this.onToggleVisible,
    required this.onResize,
    required this.onSetContextPanelTab,
    required this.onSetExplorerMode,
    required this.onSetGitDiffViewMode,
    this.onFocusSourceControlFolder,
    this.onClearSourceControlRoot,
    required this.onOpenFile,
    required this.onOpenGitDiff,
    required this.onOpenGitCommitDiff,
    required this.onOpenSearchMatch,
    required this.onPathMoved,
    this.onFocusTerminal,
    this.onOpenPullRequest,
    this.onOpenArtifact,
    this.onSourceControlAction,
  });

  final Workspace workspace;
  final WorkbenchViewPrefs prefs;
  final WorkspaceSourceControlScope? sourceControlScope;
  final bool sourceControlAvailable;
  final String? focusedSourceControlRoot;
  final VoidCallback onToggleVisible;
  final ValueChanged<double> onResize;
  final ValueChanged<WorkbenchContextPanelTab> onSetContextPanelTab;
  final ValueChanged<WorkspaceExplorerMode> onSetExplorerMode;
  final ValueChanged<GitDiffViewMode> onSetGitDiffViewMode;
  final Future<bool> Function(String relativePath)? onFocusSourceControlFolder;
  final VoidCallback? onClearSourceControlRoot;
  final ValueChanged<String> onOpenFile;
  final OpenGitDiffTabCallback onOpenGitDiff;
  final OpenGitCommitDiffTabCallback onOpenGitCommitDiff;
  final ValueChanged<WorkspaceSearchMatchTarget> onOpenSearchMatch;
  final Future<void> Function(String oldRelativePath, String newRelativePath)
  onPathMoved;
  final AgentCanvasTerminalFocuser? onFocusTerminal;
  final VoidCallback? onOpenPullRequest;
  final AgentCanvasArtifactOpener? onOpenArtifact;
  final AgentCanvasSourceControlAction? onSourceControlAction;

  @override
  Widget build(BuildContext context) {
    final sourceControlScope = _effectiveSourceControlScope;
    final activeTab = _effectiveActiveTab;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AleraTokens.surfaceVariant,
        border: Border(left: BorderSide(color: AleraTokens.borderSubtle)),
      ),
      child: prefs.rightSidebarVisible
          ? _ResizableRightSidebar(
              persistedWidth: prefs.rightSidebarWidth,
              onPersistWidth: onResize,
              child: Column(
                children: <Widget>[
                  _ContextTabHeader(
                    activeTab: activeTab,
                    sourceControlAvailable: sourceControlScope != null,
                    onSetActiveTab: onSetContextPanelTab,
                    onToggleVisible: onToggleVisible,
                  ),
                  Expanded(
                    child: switch (activeTab) {
                      WorkbenchContextPanelTab.explorer => WorkspaceExplorer(
                        key: ValueKey<String>(
                          'workspace-explorer:${workspace.id}:${workspace.path}',
                        ),
                        workspace: workspace,
                        mode: prefs.explorerMode,
                        onModeChanged: onSetExplorerMode,
                        onOpenFile: onOpenFile,
                        focusedSourceControlRoot: focusedSourceControlRoot,
                        onFocusSourceControlFolder: onFocusSourceControlFolder,
                        onClearSourceControlRoot: onClearSourceControlRoot,
                        onPathMoved: onPathMoved,
                      ),
                      WorkbenchContextPanelTab.search => WorkspaceSearchPanel(
                        workspace: workspace,
                        onOpenMatch: onOpenSearchMatch,
                      ),
                      WorkbenchContextPanelTab.gitDiff => WorkspaceGitDiffPanel(
                        workspace: workspace,
                        sourceControlScope: sourceControlScope!,
                        viewMode: prefs.gitDiffViewMode,
                        onViewModeChanged: onSetGitDiffViewMode,
                        onOpenGitDiff: onOpenGitDiff,
                        onOpenGitCommitDiff: onOpenGitCommitDiff,
                        onClearSourceControlRoot:
                            sourceControlScope.isWorkspaceRoot
                            ? null
                            : onClearSourceControlRoot,
                      ),
                      WorkbenchContextPanelTab.pullRequests =>
                        WorkspacePullRequestsPanel(
                          key: ValueKey<String>(
                            'workspace-pull-requests:${workspace.id}:${sourceControlScope!.path}',
                          ),
                          workspace: workspace,
                          repoPath: sourceControlScope.path,
                        ),
                      WorkbenchContextPanelTab.agentCanvas => AgentCanvasPanel(
                        workspace: workspace,
                        onOpenFile: (relativePath) async {
                          onOpenFile(relativePath);
                        },
                        onOpenDiff: (relativePath) async {
                          final sourceRelativePath = sourceControlScope
                              ?.toSourceRelativePath(relativePath);
                          if (sourceControlScope == null ||
                              sourceRelativePath == null) {
                            return;
                          }
                          await onOpenGitDiff(
                            relativePath: sourceRelativePath,
                            gitDiffRoot: sourceControlScope.relativeRoot,
                            scope: WorkspaceGitDiffScope.file,
                          );
                        },
                        onFocusTerminal: onFocusTerminal ?? (_) {},
                        onOpenPullRequest: onOpenPullRequest ?? () {},
                        onOpenArtifact: onOpenArtifact ?? (_) {},
                        onSwitchContextPanel: onSetContextPanelTab,
                        onSourceControlAction: onSourceControlAction,
                      ),
                    },
                  ),
                ],
              ),
            )
          : _CollapsedContextRail(
              activeTab: activeTab,
              sourceControlAvailable: sourceControlScope != null,
              onOpenTab: (tab) {
                onSetContextPanelTab(tab);
                onToggleVisible();
              },
              onToggleVisible: onToggleVisible,
            ),
    );
  }

  WorkbenchContextPanelTab get _effectiveActiveTab {
    if (_effectiveSourceControlScope == null &&
        (prefs.activeContextPanelTab == WorkbenchContextPanelTab.gitDiff ||
            prefs.activeContextPanelTab ==
                WorkbenchContextPanelTab.pullRequests)) {
      return WorkbenchContextPanelTab.explorer;
    }
    return prefs.activeContextPanelTab;
  }

  WorkspaceSourceControlScope? get _effectiveSourceControlScope {
    if (sourceControlScope != null) {
      return sourceControlScope;
    }
    if (!sourceControlAvailable) {
      return null;
    }
    return WorkspaceSourceControlScope(
      workspaceId: workspace.id,
      workspacePath: workspace.path,
      path: workspace.path,
    );
  }
}

class _ResizableRightSidebar extends StatefulWidget {
  const _ResizableRightSidebar({
    required this.persistedWidth,
    required this.onPersistWidth,
    required this.child,
  });

  final double persistedWidth;
  final ValueChanged<double> onPersistWidth;
  final Widget child;

  @override
  State<_ResizableRightSidebar> createState() => _ResizableRightSidebarState();
}

class _ResizableRightSidebarState extends State<_ResizableRightSidebar> {
  double? _transientWidth;

  double get _width => _transientWidth ?? widget.persistedWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _RightResizeHandle(
          currentWidth: _width,
          onResize: (width) {
            setState(() {
              _transientWidth = width.clamp(
                AleraTokens.sidebarMinWidth,
                AleraTokens.sidebarMaxWidth,
              );
            });
          },
          onResizeEnd: (width) {
            widget.onPersistWidth(width);
            setState(() => _transientWidth = null);
          },
        ),
        SizedBox(width: _width, child: widget.child),
      ],
    );
  }
}

class _CollapsedContextRail extends StatelessWidget {
  const _CollapsedContextRail({
    required this.activeTab,
    required this.sourceControlAvailable,
    required this.onOpenTab,
    required this.onToggleVisible,
  });

  final WorkbenchContextPanelTab activeTab;
  final bool sourceControlAvailable;
  final ValueChanged<WorkbenchContextPanelTab> onOpenTab;
  final VoidCallback onToggleVisible;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AleraTokens.sidebarCollapsedWidth,
      child: Column(
        children: <Widget>[
          const SizedBox(height: AleraTokens.space8),
          _ContextTabButton(
            tab: WorkbenchContextPanelTab.explorer,
            activeTab: activeTab,
            tooltip: 'Explorer',
            icon: AleraIcons.copyFiles,
            onPressed: () => onOpenTab(WorkbenchContextPanelTab.explorer),
          ),
          const SizedBox(height: AleraTokens.space6),
          _ContextTabButton(
            tab: WorkbenchContextPanelTab.search,
            activeTab: activeTab,
            tooltip: 'Search',
            icon: AleraIcons.search,
            onPressed: () => onOpenTab(WorkbenchContextPanelTab.search),
          ),
          if (sourceControlAvailable) ...<Widget>[
            const SizedBox(height: AleraTokens.space6),
            _ContextTabButton(
              tab: WorkbenchContextPanelTab.gitDiff,
              activeTab: activeTab,
              tooltip: 'Source Control',
              icon: AleraIcons.gitBranch,
              onPressed: () => onOpenTab(WorkbenchContextPanelTab.gitDiff),
            ),
            const SizedBox(height: AleraTokens.space6),
            _ContextTabButton(
              tab: WorkbenchContextPanelTab.pullRequests,
              activeTab: activeTab,
              tooltip: 'Pull Request',
              icon: AleraIcons.gitPullRequest,
              onPressed: () => onOpenTab(WorkbenchContextPanelTab.pullRequests),
            ),
          ],
          const SizedBox(height: AleraTokens.space6),
          _ContextTabButton(
            tab: WorkbenchContextPanelTab.agentCanvas,
            activeTab: activeTab,
            tooltip: 'Agent Canvas',
            icon: AleraIcons.agent,
            onPressed: () => onOpenTab(WorkbenchContextPanelTab.agentCanvas),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: AleraTokens.space8),
            child: AleraIconButton(
              tooltip: 'Expand panel',
              icon: AleraIcons.chevronsLeft,
              onPressed: onToggleVisible,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextTabHeader extends StatelessWidget {
  const _ContextTabHeader({
    required this.activeTab,
    required this.sourceControlAvailable,
    required this.onSetActiveTab,
    required this.onToggleVisible,
  });

  final WorkbenchContextPanelTab activeTab;
  final bool sourceControlAvailable;
  final ValueChanged<WorkbenchContextPanelTab> onSetActiveTab;
  final VoidCallback onToggleVisible;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AleraTokens.surfaceVariant,
        border: Border(bottom: BorderSide(color: AleraTokens.borderSubtle)),
      ),
      child: SizedBox(
        height: AleraTokens.sidebarHeaderHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
          child: Row(
            children: <Widget>[
              _ContextTabButton(
                tab: WorkbenchContextPanelTab.explorer,
                activeTab: activeTab,
                tooltip: 'Explorer',
                icon: AleraIcons.copyFiles,
                onPressed: () =>
                    onSetActiveTab(WorkbenchContextPanelTab.explorer),
              ),
              const SizedBox(width: AleraTokens.space6),
              _ContextTabButton(
                tab: WorkbenchContextPanelTab.search,
                activeTab: activeTab,
                tooltip: 'Search',
                icon: AleraIcons.search,
                onPressed: () =>
                    onSetActiveTab(WorkbenchContextPanelTab.search),
              ),
              if (sourceControlAvailable) ...<Widget>[
                const SizedBox(width: AleraTokens.space6),
                _ContextTabButton(
                  tab: WorkbenchContextPanelTab.gitDiff,
                  activeTab: activeTab,
                  tooltip: 'Source Control',
                  icon: AleraIcons.gitBranch,
                  onPressed: () =>
                      onSetActiveTab(WorkbenchContextPanelTab.gitDiff),
                ),
                const SizedBox(width: AleraTokens.space6),
                _ContextTabButton(
                  tab: WorkbenchContextPanelTab.pullRequests,
                  activeTab: activeTab,
                  tooltip: 'Pull Request',
                  icon: AleraIcons.gitPullRequest,
                  onPressed: () =>
                      onSetActiveTab(WorkbenchContextPanelTab.pullRequests),
                ),
              ],
              const SizedBox(width: AleraTokens.space6),
              _ContextTabButton(
                tab: WorkbenchContextPanelTab.agentCanvas,
                activeTab: activeTab,
                tooltip: 'Agent Canvas',
                icon: AleraIcons.agent,
                onPressed: () =>
                    onSetActiveTab(WorkbenchContextPanelTab.agentCanvas),
              ),
              const Spacer(),
              AleraIconButton(
                tooltip: 'Collapse panel',
                icon: AleraIcons.chevronsRight,
                onPressed: onToggleVisible,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContextTabButton extends StatelessWidget {
  const _ContextTabButton({
    required this.tab,
    required this.activeTab,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final WorkbenchContextPanelTab tab;
  final WorkbenchContextPanelTab activeTab;
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final active = tab == activeTab;
    return AleraIconButton(
      tooltip: tooltip,
      icon: icon,
      onPressed: onPressed,
      iconColor: active ? AleraTokens.foreground : AleraTokens.foregroundMuted,
      backgroundColor: active ? AleraTokens.surfaceElevated : null,
      borderColor: active ? AleraTokens.border : AleraTokens.borderSubtle,
    );
  }
}

class _RightResizeHandle extends StatefulWidget {
  const _RightResizeHandle({
    required this.currentWidth,
    required this.onResize,
    required this.onResizeEnd,
  });

  final double currentWidth;
  final ValueChanged<double> onResize;
  final ValueChanged<double> onResizeEnd;

  @override
  State<_RightResizeHandle> createState() => _RightResizeHandleState();
}

class _RightResizeHandleState extends State<_RightResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;
  double? _dragWidth;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) {
          _dragWidth = widget.currentWidth;
          setState(() => _dragging = true);
        },
        onHorizontalDragEnd: (_) => _stopDragging(),
        onHorizontalDragCancel: _stopDragging,
        onHorizontalDragUpdate: (details) {
          final next = (_dragWidth ?? widget.currentWidth) - details.delta.dx;
          _dragWidth = next;
          widget.onResize(next);
        },
        child: SizedBox(
          width: AleraTokens.space6,
          child: Center(
            child: AnimatedContainer(
              duration: AleraTokens.durationFast,
              width: active ? 2 : 1,
              color: active ? AleraTokens.border : AleraTokens.borderSubtle,
            ),
          ),
        ),
      ),
    );
  }

  void _stopDragging() {
    final finalWidth = _dragWidth ?? widget.currentWidth;
    _dragWidth = null;
    setState(() => _dragging = false);
    widget.onResizeEnd(finalWidth);
  }
}
