part of 'workspace_git_diff_panel.dart';

class _GitDiffGroups extends StatelessWidget {
  const _GitDiffGroups({
    required this.groups,
    required this.workspacePath,
    required this.viewMode,
    required this.busy,
    required this.collapsedSections,
    required this.collapsedTreeNodes,
    required this.expandedSubmodules,
    required this.onToggleSection,
    required this.onToggleTreeNode,
    required this.onToggleSubmodule,
    required this.onOpenGitDiff,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
    required this.onStageArea,
    required this.onUnstageArea,
    required this.onDiscardArea,
    required this.onStagePath,
    required this.onUnstagePath,
    required this.onDiscardPath,
  });

  final List<GitChangeGroup> groups;
  final String workspacePath;
  final GitDiffViewMode viewMode;
  final bool busy;
  final Set<String> collapsedSections;
  final Set<String> collapsedTreeNodes;
  final Set<String> expandedSubmodules;
  final ValueChanged<String> onToggleSection;
  final ValueChanged<String> onToggleTreeNode;
  final ValueChanged<GitChangeEntry> onToggleSubmodule;
  final OpenGitDiffTabCallback onOpenGitDiff;
  final ValueChanged<GitChangeEntry> onStage;
  final ValueChanged<GitChangeEntry> onUnstage;
  final ValueChanged<GitChangeEntry> onDiscard;
  final void Function(GitChangeArea area, String? filePath) onStageArea;
  final void Function(GitChangeArea area, String? filePath) onUnstageArea;
  final void Function(GitChangeArea area, String? filePath) onDiscardArea;
  final ValueChanged<String?> onStagePath;
  final ValueChanged<String?> onUnstagePath;
  final ValueChanged<String?> onDiscardPath;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space6),
      children: <Widget>[
        for (final group in groups)
          _GitDiffGroup(
            group: group,
            workspacePath: workspacePath,
            viewMode: viewMode,
            busy: busy,
            collapsed: collapsedSections.contains(_sectionKeyForGroup(group)),
            collapsedTreeNodes: collapsedTreeNodes,
            expandedSubmodules: expandedSubmodules,
            onToggleSection: onToggleSection,
            onToggleTreeNode: onToggleTreeNode,
            onToggleSubmodule: onToggleSubmodule,
            onOpenGitDiff: onOpenGitDiff,
            onStage: onStage,
            onUnstage: onUnstage,
            onDiscard: onDiscard,
            onStageArea: onStageArea,
            onUnstageArea: onUnstageArea,
            onDiscardArea: onDiscardArea,
            onStagePath: onStagePath,
            onUnstagePath: onUnstagePath,
            onDiscardPath: onDiscardPath,
          ),
      ],
    );
  }
}

class _GitDiffGroup extends StatelessWidget {
  const _GitDiffGroup({
    required this.group,
    required this.workspacePath,
    required this.viewMode,
    required this.busy,
    required this.collapsed,
    required this.collapsedTreeNodes,
    required this.expandedSubmodules,
    required this.onToggleSection,
    required this.onToggleTreeNode,
    required this.onToggleSubmodule,
    required this.onOpenGitDiff,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
    required this.onStageArea,
    required this.onUnstageArea,
    required this.onDiscardArea,
    required this.onStagePath,
    required this.onUnstagePath,
    required this.onDiscardPath,
  });

  final GitChangeGroup group;
  final String workspacePath;
  final GitDiffViewMode viewMode;
  final bool busy;
  final bool collapsed;
  final Set<String> collapsedTreeNodes;
  final Set<String> expandedSubmodules;
  final ValueChanged<String> onToggleSection;
  final ValueChanged<String> onToggleTreeNode;
  final ValueChanged<GitChangeEntry> onToggleSubmodule;
  final OpenGitDiffTabCallback onOpenGitDiff;
  final ValueChanged<GitChangeEntry> onStage;
  final ValueChanged<GitChangeEntry> onUnstage;
  final ValueChanged<GitChangeEntry> onDiscard;
  final void Function(GitChangeArea area, String? filePath) onStageArea;
  final void Function(GitChangeArea area, String? filePath) onUnstageArea;
  final void Function(GitChangeArea area, String? filePath) onDiscardArea;
  final ValueChanged<String?> onStagePath;
  final ValueChanged<String?> onUnstagePath;
  final ValueChanged<String?> onDiscardPath;

  @override
  Widget build(BuildContext context) {
    if (group.entries.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _GitDiffGroupHeader(
            group: group,
            collapsed: collapsed,
            busy: busy,
            onToggleCollapsed: () =>
                onToggleSection(_sectionKeyForGroup(group)),
            onStage: () => group.unified
                ? onStagePath(null)
                : onStageArea(group.area, null),
            onUnstage: () => group.unified
                ? onUnstagePath(null)
                : onUnstageArea(group.area, null),
            onDiscard: () => group.unified
                ? onDiscardPath(null)
                : onDiscardArea(group.area, null),
            canStage: group.entries.any((entry) => entry.canStageFromParent),
            canUnstage: group.entries.any(
              (entry) => entry.canUnstageFromParent,
            ),
            canDiscard: group.entries.any(
              (entry) => entry.canDiscardFromParent,
            ),
          ),
          if (!collapsed) ...<Widget>[
            if (viewMode == GitDiffViewMode.flat)
              for (final entry in group.entries) ...<Widget>[
                _GitDiffFileRow(
                  entry: entry,
                  absolutePath: _terminalPathForGitEntry(
                    workspacePath,
                    entry.path,
                  ),
                  depth: 0,
                  showRelativePath: true,
                  showAreaMarker: group.unified,
                  busy: busy,
                  onStage: onStage,
                  onUnstage: onUnstage,
                  onDiscard: onDiscard,
                  submoduleExpanded: expandedSubmodules.contains(entry.id),
                  onToggleSubmodule: () => onToggleSubmodule(entry),
                  onTap: entry.isSubmoduleWorktreeOnly
                      ? () => onToggleSubmodule(entry)
                      : () => unawaited(
                          onOpenGitDiff(
                            relativePath: entry.path,
                            area: entry.area,
                            scope: WorkspaceGitDiffScope.file,
                          ),
                        ),
                ),
                if (entry.isExpandableSubmodule &&
                    expandedSubmodules.contains(entry.id))
                  _SubmoduleChanges(
                    workspacePath: workspacePath,
                    entry: entry,
                    depth: 1,
                    busy: busy,
                    onOpenGitDiff: onOpenGitDiff,
                  ),
              ]
            else
              _GitDiffTree(
                workspacePath: workspacePath,
                area: group.area,
                rows: group.treeRows,
                busy: busy,
                collapsedTreeNodes: collapsedTreeNodes,
                expandedSubmodules: expandedSubmodules,
                onToggleTreeNode: onToggleTreeNode,
                onToggleSubmodule: onToggleSubmodule,
                onOpenGitDiff: onOpenGitDiff,
                onStage: onStage,
                onUnstage: onUnstage,
                onDiscard: onDiscard,
                onStageArea: onStageArea,
                onUnstageArea: onUnstageArea,
                onDiscardArea: onDiscardArea,
                showAreaMarker: group.unified,
                unified: group.unified,
                onStagePath: onStagePath,
                onUnstagePath: onUnstagePath,
                onDiscardPath: onDiscardPath,
              ),
          ],
        ],
      ),
    );
  }
}

String _sectionKeyForGroup(GitChangeGroup group) {
  return group.unified ? 'section:unified' : 'section:${group.area.key}';
}

class _GitDiffGroupHeader extends StatelessWidget {
  const _GitDiffGroupHeader({
    required this.group,
    required this.collapsed,
    required this.busy,
    required this.onToggleCollapsed,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
    required this.canStage,
    required this.canUnstage,
    required this.canDiscard,
  });

  final GitChangeGroup group;
  final bool collapsed;
  final bool busy;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onStage;
  final VoidCallback onUnstage;
  final VoidCallback onDiscard;
  final bool canStage;
  final bool canUnstage;
  final bool canDiscard;

  @override
  Widget build(BuildContext context) {
    return _GitDiffBaseRow(
      depth: 0,
      onTap: onToggleCollapsed,
      child: Row(
        children: <Widget>[
          Icon(
            collapsed ? AleraIcons.chevronRight : AleraIcons.chevronDown,
            size: 14,
            color: AleraTokens.foregroundMuted,
          ),
          const SizedBox(width: AleraTokens.space4),
          Expanded(
            child: Text(
              group.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ),
          Text(
            '${group.entries.length}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AleraTokens.foregroundFaint,
            ),
          ),
          const SizedBox(width: AleraTokens.space6),
          _AreaActions(
            busy: busy,
            onStage: onStage,
            onUnstage: onUnstage,
            onDiscard: onDiscard,
            canStage: canStage,
            canUnstage: canUnstage,
            canDiscard: canDiscard,
          ),
        ],
      ),
    );
  }
}

class _GitDiffMessage extends StatelessWidget {
  const _GitDiffMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space16),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AleraTokens.foregroundMuted),
        ),
      ),
    );
  }
}
