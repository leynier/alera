part of 'workspace_git_diff_panel.dart';

class _GitDiffTree extends StatefulWidget {
  const _GitDiffTree({
    required this.workspacePath,
    required this.area,
    required this.rows,
    required this.busy,
    required this.collapsedTreeNodes,
    required this.expandedSubmodules,
    required this.onToggleTreeNode,
    required this.onToggleSubmodule,
    required this.onOpenGitDiff,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
    required this.onStageArea,
    required this.onUnstageArea,
    required this.onDiscardArea,
  });

  final String workspacePath;
  final GitChangeArea area;
  final List<GitChangeTreeRow> rows;
  final bool busy;
  final Set<String> collapsedTreeNodes;
  final Set<String> expandedSubmodules;
  final void Function(GitChangeArea area, String path) onToggleTreeNode;
  final ValueChanged<GitChangeEntry> onToggleSubmodule;
  final OpenGitDiffTabCallback onOpenGitDiff;
  final ValueChanged<GitChangeEntry> onStage;
  final ValueChanged<GitChangeEntry> onUnstage;
  final ValueChanged<GitChangeEntry> onDiscard;
  final void Function(GitChangeArea area, String? filePath) onStageArea;
  final void Function(GitChangeArea area, String? filePath) onUnstageArea;
  final void Function(GitChangeArea area, String? filePath) onDiscardArea;

  @override
  State<_GitDiffTree> createState() => _GitDiffTreeState();
}

class _GitDiffTreeState extends State<_GitDiffTree> {
  @override
  Widget build(BuildContext context) {
    final rows = widget.rows.isEmpty ? _fallbackRows() : widget.rows;
    final directoryCapabilities = _directoryCapabilities(rows);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final row in _visibleRows(rows))
          ..._buildRows(row, directoryCapabilities),
      ],
    );
  }

  Map<String, _GitDirectoryCapabilities> _directoryCapabilities(
    List<GitChangeTreeRow> rows,
  ) {
    final result = <String, _GitDirectoryCapabilities>{};
    for (final row in rows) {
      final entry = row.entry;
      if (entry == null) {
        continue;
      }
      final parts = entry.path
          .split('/')
          .where((part) => part.isNotEmpty)
          .toList(growable: false);
      var directoryPath = '';
      for (var index = 0; index < parts.length - 1; index += 1) {
        directoryPath = directoryPath.isEmpty
            ? parts[index]
            : '$directoryPath/${parts[index]}';
        result
            .putIfAbsent(directoryPath, _GitDirectoryCapabilities.new)
            .include(entry);
      }
    }
    return result;
  }

  Iterable<GitChangeTreeRow> _visibleRows(List<GitChangeTreeRow> rows) sync* {
    int? collapsedDepth;
    for (final row in rows) {
      final hiddenDepth = collapsedDepth;
      if (hiddenDepth != null) {
        if (row.depth > hiddenDepth) {
          continue;
        }
        collapsedDepth = null;
      }
      yield row;
      if (row.kind == GitChangeTreeRowKind.directory &&
          widget.collapsedTreeNodes.contains(_treeNodeKey(row.path))) {
        collapsedDepth = row.depth;
      }
    }
  }

  List<Widget> _buildRows(
    GitChangeTreeRow row,
    Map<String, _GitDirectoryCapabilities> directoryCapabilities,
  ) {
    if (row.entry case final entry?) {
      final expanded = widget.expandedSubmodules.contains(entry.id);
      return <Widget>[
        _GitDiffFileRow(
          entry: entry,
          depth: row.depth,
          busy: widget.busy,
          onStage: widget.onStage,
          onUnstage: widget.onUnstage,
          onDiscard: widget.onDiscard,
          submoduleExpanded: expanded,
          onToggleSubmodule: () => widget.onToggleSubmodule(entry),
          onTap: entry.isSubmoduleWorktreeOnly
              ? () => widget.onToggleSubmodule(entry)
              : () => unawaited(
                  widget.onOpenGitDiff(
                    relativePath: entry.path,
                    area: entry.area,
                    scope: WorkspaceGitDiffScope.file,
                  ),
                ),
        ),
        if (entry.isExpandableSubmodule && expanded)
          _SubmoduleChanges(
            workspacePath: widget.workspacePath,
            entry: entry,
            depth: row.depth + 1,
            busy: widget.busy,
            onOpenGitDiff: widget.onOpenGitDiff,
          ),
      ];
    }
    final collapsed = widget.collapsedTreeNodes.contains(
      _treeNodeKey(row.path),
    );
    final capabilities = directoryCapabilities[row.path];
    return <Widget>[
      _GitDiffDirectoryRow(
        row: row,
        busy: widget.busy,
        collapsed: collapsed,
        canStage: capabilities?.canStage ?? false,
        canUnstage: capabilities?.canUnstage ?? false,
        canDiscard: capabilities?.canDiscard ?? false,
        onTap: () => widget.onToggleTreeNode(widget.area, row.path),
        onStage: () => widget.onStageArea(widget.area, row.path),
        onUnstage: () => widget.onUnstageArea(widget.area, row.path),
        onDiscard: () => widget.onDiscardArea(widget.area, row.path),
      ),
    ];
  }

  List<GitChangeTreeRow> _fallbackRows() {
    return const <GitChangeTreeRow>[];
  }

  String _treeNodeKey(String path) => 'folder:${widget.area.key}:$path';
}

class _GitDirectoryCapabilities {
  bool canStage = false;
  bool canUnstage = false;
  bool canDiscard = false;

  void include(GitChangeEntry entry) {
    canStage = canStage || entry.canStageFromParent;
    canUnstage = canUnstage || entry.canUnstageFromParent;
    canDiscard = canDiscard || entry.canDiscardFromParent;
  }
}

class _GitDiffDirectoryRow extends StatelessWidget {
  const _GitDiffDirectoryRow({
    required this.row,
    required this.busy,
    required this.collapsed,
    required this.canStage,
    required this.canUnstage,
    required this.canDiscard,
    required this.onTap,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
  });

  final GitChangeTreeRow row;
  final bool busy;
  final bool collapsed;
  final bool canStage;
  final bool canUnstage;
  final bool canDiscard;
  final VoidCallback onTap;
  final VoidCallback onStage;
  final VoidCallback onUnstage;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return _GitDiffBaseRow(
      depth: row.depth,
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Icon(
            collapsed ? AleraIcons.chevronRight : AleraIcons.chevronDown,
            size: 14,
            color: AleraTokens.foregroundMuted,
          ),
          const SizedBox(width: AleraTokens.space2),
          AleraFileIcon(
            pathOrName: row.name,
            kind: AleraFileIconKind.folder,
            isExpanded: !collapsed,
            size: 15,
          ),
          const SizedBox(width: AleraTokens.space6),
          Expanded(
            child: Text(
              row.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ),
          Text(
            '${row.fileCount}',
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

class _GitDiffFileRow extends StatelessWidget {
  const _GitDiffFileRow({
    required this.entry,
    required this.depth,
    required this.onTap,
    required this.busy,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
    this.showRelativePath = false,
    this.submoduleExpanded = false,
    this.onToggleSubmodule,
  });

  final GitChangeEntry entry;
  final int depth;
  final VoidCallback onTap;
  final bool busy;
  final ValueChanged<GitChangeEntry> onStage;
  final ValueChanged<GitChangeEntry> onUnstage;
  final ValueChanged<GitChangeEntry> onDiscard;
  final bool showRelativePath;
  final bool submoduleExpanded;
  final VoidCallback? onToggleSubmodule;

  @override
  Widget build(BuildContext context) {
    return _GitDiffBaseRow(
      depth: depth,
      onTap: onTap,
      child: Row(
        children: <Widget>[
          if (entry.isExpandableSubmodule)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggleSubmodule,
              child: Padding(
                padding: const EdgeInsets.only(right: AleraTokens.space2),
                child: Icon(
                  submoduleExpanded
                      ? AleraIcons.chevronDown
                      : AleraIcons.chevronRight,
                  size: 14,
                  color: AleraTokens.foregroundMuted,
                ),
              ),
            )
          else
            const SizedBox(width: 16),
          AleraFileIcon(
            pathOrName: entry.path,
            kind: AleraFileIconKind.file,
            size: 15,
          ),
          const SizedBox(width: AleraTokens.space6),
          Expanded(
            child: Text(
              showRelativePath ? entry.path : entry.path.split('/').last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ),
          if (entry.isSubmoduleWorktreeOnly)
            Tooltip(
              message: 'Manage Inside Submodule',
              child: Text(
                'Inside',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AleraTokens.foregroundFaint,
                ),
              ),
            ),
          if (entry.isSubmoduleWorktreeOnly)
            const SizedBox(width: AleraTokens.space4),
          _GitStatusLabel(status: entry.status),
          const SizedBox(width: AleraTokens.space6),
          _LineStats(added: entry.added, removed: entry.removed),
          const SizedBox(width: AleraTokens.space4),
          _GitFileActions(
            entry: entry,
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

class _GitFileActions extends StatelessWidget {
  const _GitFileActions({
    required this.entry,
    required this.busy,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
  });

  final GitChangeEntry entry;
  final bool busy;
  final ValueChanged<GitChangeEntry> onStage;
  final ValueChanged<GitChangeEntry> onUnstage;
  final ValueChanged<GitChangeEntry> onDiscard;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          if (entry.canUnstageFromParent)
            AleraIconButton(
              tooltip: 'Unstage',
              icon: AleraIcons.remove,
              onPressed: busy ? null : () => onUnstage(entry),
            )
          else if (entry.canStageFromParent)
            AleraIconButton(
              tooltip: 'Stage',
              icon: AleraIcons.add,
              onPressed: busy ? null : () => onStage(entry),
            ),
          if (entry.canDiscardFromParent)
            AleraIconButton(
              tooltip: 'Discard',
              icon: AleraIcons.close,
              onPressed: busy ? null : () => onDiscard(entry),
            ),
        ],
      ),
    );
  }
}

class _AreaActions extends StatelessWidget {
  const _AreaActions({
    required this.busy,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
    required this.canStage,
    required this.canUnstage,
    required this.canDiscard,
  });

  final bool busy;
  final VoidCallback onStage;
  final VoidCallback onUnstage;
  final VoidCallback onDiscard;
  final bool canStage;
  final bool canUnstage;
  final bool canDiscard;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          if (canUnstage)
            AleraIconButton(
              tooltip: 'Unstage',
              icon: AleraIcons.remove,
              onPressed: busy ? null : onUnstage,
            )
          else if (canStage)
            AleraIconButton(
              tooltip: 'Stage',
              icon: AleraIcons.add,
              onPressed: busy ? null : onStage,
            ),
          if (canDiscard)
            AleraIconButton(
              tooltip: 'Discard',
              icon: AleraIcons.close,
              onPressed: busy ? null : onDiscard,
            ),
        ],
      ),
    );
  }
}

class _GitDiffBaseRow extends StatelessWidget {
  const _GitDiffBaseRow({
    required this.depth,
    required this.child,
    required this.onTap,
  });

  final int depth;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.only(
            left: AleraTokens.space8 + (depth * AleraTokens.space12),
            right: AleraTokens.space8,
            top: AleraTokens.space4,
            bottom: AleraTokens.space4,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _LineStats extends StatelessWidget {
  const _LineStats({required this.added, required this.removed});

  final int? added;
  final int? removed;

  @override
  Widget build(BuildContext context) {
    final visibleAdded = added != null && added! > 0 ? added : null;
    final visibleRemoved = removed != null && removed! > 0 ? removed : null;
    if (visibleAdded == null && visibleRemoved == null) {
      return const SizedBox(width: 64);
    }
    final style = Theme.of(context).textTheme.labelSmall;
    return SizedBox(
      width: 64,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          if (visibleAdded case final added?)
            Flexible(
              child: Text(
                '+$added',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style?.copyWith(color: AleraTokens.success),
              ),
            ),
          if (visibleRemoved case final removed?) ...<Widget>[
            const SizedBox(width: AleraTokens.space4),
            Flexible(
              child: Text(
                '-$removed',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style?.copyWith(color: AleraTokens.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GitStatusLabel extends StatelessWidget {
  const _GitStatusLabel({required this.status});

  final GitChangeStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      GitChangeStatus.added => ('A', AleraTokens.success),
      GitChangeStatus.untracked => ('U', AleraTokens.success),
      GitChangeStatus.deleted => ('D', AleraTokens.error),
      GitChangeStatus.renamed => ('R', AleraTokens.warning),
      GitChangeStatus.copied => ('C', AleraTokens.warning),
      GitChangeStatus.modified => ('M', AleraTokens.warning),
    };
    return SizedBox(
      width: 12,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
