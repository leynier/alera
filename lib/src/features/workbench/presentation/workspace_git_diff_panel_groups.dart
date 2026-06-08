part of 'workspace_git_diff_panel.dart';

class _GitDiffGroups extends StatelessWidget {
  const _GitDiffGroups({
    required this.groups,
    required this.viewMode,
    required this.busy,
    required this.collapsedSections,
    required this.collapsedTreeNodes,
    required this.onToggleSection,
    required this.onToggleTreeNode,
    required this.onOpenGitDiff,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
    required this.onStageArea,
    required this.onUnstageArea,
    required this.onDiscardArea,
  });

  final List<GitChangeGroup> groups;
  final GitDiffViewMode viewMode;
  final bool busy;
  final Set<String> collapsedSections;
  final Set<String> collapsedTreeNodes;
  final ValueChanged<GitChangeArea> onToggleSection;
  final void Function(GitChangeArea area, String path) onToggleTreeNode;
  final OpenGitDiffTabCallback onOpenGitDiff;
  final ValueChanged<GitChangeEntry> onStage;
  final ValueChanged<GitChangeEntry> onUnstage;
  final ValueChanged<GitChangeEntry> onDiscard;
  final void Function(GitChangeArea area, String? filePath) onStageArea;
  final void Function(GitChangeArea area, String? filePath) onUnstageArea;
  final void Function(GitChangeArea area, String? filePath) onDiscardArea;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space6),
      children: <Widget>[
        for (final group in groups)
          _GitDiffGroup(
            group: group,
            viewMode: viewMode,
            busy: busy,
            collapsed: collapsedSections.contains('section:${group.area.key}'),
            collapsedTreeNodes: collapsedTreeNodes,
            onToggleSection: onToggleSection,
            onToggleTreeNode: onToggleTreeNode,
            onOpenGitDiff: onOpenGitDiff,
            onStage: onStage,
            onUnstage: onUnstage,
            onDiscard: onDiscard,
            onStageArea: onStageArea,
            onUnstageArea: onUnstageArea,
            onDiscardArea: onDiscardArea,
          ),
      ],
    );
  }
}

class _GitDiffGroup extends StatelessWidget {
  const _GitDiffGroup({
    required this.group,
    required this.viewMode,
    required this.busy,
    required this.collapsed,
    required this.collapsedTreeNodes,
    required this.onToggleSection,
    required this.onToggleTreeNode,
    required this.onOpenGitDiff,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
    required this.onStageArea,
    required this.onUnstageArea,
    required this.onDiscardArea,
  });

  final GitChangeGroup group;
  final GitDiffViewMode viewMode;
  final bool busy;
  final bool collapsed;
  final Set<String> collapsedTreeNodes;
  final ValueChanged<GitChangeArea> onToggleSection;
  final void Function(GitChangeArea area, String path) onToggleTreeNode;
  final OpenGitDiffTabCallback onOpenGitDiff;
  final ValueChanged<GitChangeEntry> onStage;
  final ValueChanged<GitChangeEntry> onUnstage;
  final ValueChanged<GitChangeEntry> onDiscard;
  final void Function(GitChangeArea area, String? filePath) onStageArea;
  final void Function(GitChangeArea area, String? filePath) onUnstageArea;
  final void Function(GitChangeArea area, String? filePath) onDiscardArea;

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
            onToggleCollapsed: () => onToggleSection(group.area),
            onStage: () => onStageArea(group.area, null),
            onUnstage: () => onUnstageArea(group.area, null),
            onDiscard: () => onDiscardArea(group.area, null),
          ),
          if (!collapsed) ...<Widget>[
            if (viewMode == GitDiffViewMode.flat)
              for (final entry in group.entries)
                _GitDiffFileRow(
                  entry: entry,
                  depth: 0,
                  showRelativePath: true,
                  busy: busy,
                  onStage: onStage,
                  onUnstage: onUnstage,
                  onDiscard: onDiscard,
                  onTap: () => unawaited(
                    onOpenGitDiff(
                      relativePath: entry.path,
                      area: entry.area,
                      scope: WorkspaceGitDiffScope.file,
                    ),
                  ),
                )
            else
              _GitDiffTree(
                area: group.area,
                rows: group.treeRows,
                busy: busy,
                collapsedTreeNodes: collapsedTreeNodes,
                onToggleTreeNode: onToggleTreeNode,
                onOpenGitDiff: onOpenGitDiff,
                onStage: onStage,
                onUnstage: onUnstage,
                onDiscard: onDiscard,
                onStageArea: onStageArea,
                onUnstageArea: onUnstageArea,
                onDiscardArea: onDiscardArea,
              ),
          ],
        ],
      ),
    );
  }
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
  });

  final GitChangeGroup group;
  final bool collapsed;
  final bool busy;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onStage;
  final VoidCallback onUnstage;
  final VoidCallback onDiscard;

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
              group.area.label,
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
            area: group.area,
            busy: busy,
            onStage: onStage,
            onUnstage: onUnstage,
            onDiscard: onDiscard,
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
