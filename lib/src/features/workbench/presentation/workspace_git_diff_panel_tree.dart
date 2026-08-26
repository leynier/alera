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
    this.onOpenFile,
    required this.onRevealInExplorer,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
    required this.onStageArea,
    required this.onUnstageArea,
    required this.onDiscardArea,
    this.showAreaMarker = false,
    this.unified = false,
    this.onStagePath,
    this.onUnstagePath,
    this.onDiscardPath,
  });

  final String workspacePath;
  final GitChangeArea area;
  final List<GitChangeTreeRow> rows;
  final bool busy;
  final Set<String> collapsedTreeNodes;
  final Set<String> expandedSubmodules;
  final ValueChanged<String> onToggleTreeNode;
  final ValueChanged<GitChangeEntry> onToggleSubmodule;
  final OpenGitDiffTabCallback onOpenGitDiff;
  final ValueChanged<String>? onOpenFile;
  final ValueChanged<String> onRevealInExplorer;
  final ValueChanged<GitChangeEntry> onStage;
  final ValueChanged<GitChangeEntry> onUnstage;
  final ValueChanged<GitChangeEntry> onDiscard;
  final void Function(GitChangeArea area, String? filePath) onStageArea;
  final void Function(GitChangeArea area, String? filePath) onUnstageArea;
  final void Function(GitChangeArea area, String? filePath) onDiscardArea;
  final bool showAreaMarker;
  final bool unified;
  final ValueChanged<String?>? onStagePath;
  final ValueChanged<String?>? onUnstagePath;
  final ValueChanged<String?>? onDiscardPath;

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
          absolutePath: _terminalPathForGitEntry(
            widget.workspacePath,
            entry.path,
          ),
          depth: row.depth,
          busy: widget.busy,
          onOpenFile: widget.onOpenFile == null
              ? null
              : () => widget.onOpenFile!(entry.path),
          onRevealInExplorer: () => widget.onRevealInExplorer(entry.path),
          onStage: widget.onStage,
          onUnstage: widget.onUnstage,
          onDiscard: widget.onDiscard,
          showAreaMarker: widget.showAreaMarker,
          submoduleExpanded: expanded,
          onToggleSubmodule: () => widget.onToggleSubmodule(entry),
          onTap: entry.isSubmoduleWorktreeOnly
              ? () => widget.onToggleSubmodule(entry)
              : () => unawaited(
                  widget.onOpenGitDiff(
                    relativePath: entry.path,
                    area: entry.area,
                    scope: WorkspaceGitDiffScope.file,
                    preview: true,
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
            onOpenFile: widget.onOpenFile,
            onRevealInExplorer: widget.onRevealInExplorer,
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
        absolutePath: _terminalPathForGitEntry(widget.workspacePath, row.path),
        busy: widget.busy,
        collapsed: collapsed,
        canStage: capabilities?.canStage ?? false,
        canUnstage: capabilities?.canUnstage ?? false,
        canDiscard: capabilities?.canDiscard ?? false,
        onTap: () => widget.onToggleTreeNode(_treeNodeKey(row.path)),
        onOpenFile: null,
        onRevealInExplorer: () => widget.onRevealInExplorer(row.path),
        onStage: () {
          if (widget.unified) {
            widget.onStagePath?.call(row.path);
            return;
          }
          widget.onStageArea(widget.area, row.path);
        },
        onUnstage: () {
          if (widget.unified) {
            widget.onUnstagePath?.call(row.path);
            return;
          }
          widget.onUnstageArea(widget.area, row.path);
        },
        onDiscard: () {
          if (widget.unified) {
            widget.onDiscardPath?.call(row.path);
            return;
          }
          widget.onDiscardArea(widget.area, row.path);
        },
      ),
    ];
  }

  List<GitChangeTreeRow> _fallbackRows() {
    return const <GitChangeTreeRow>[];
  }

  String _treeNodeKey(String path) {
    final areaKey = widget.unified ? 'unified' : widget.area.key;
    return 'folder:$areaKey:$path';
  }
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
    required this.absolutePath,
    required this.busy,
    required this.collapsed,
    required this.canStage,
    required this.canUnstage,
    required this.canDiscard,
    required this.onTap,
    this.onOpenFile,
    required this.onRevealInExplorer,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
  });

  final GitChangeTreeRow row;
  final String absolutePath;
  final bool busy;
  final bool collapsed;
  final bool canStage;
  final bool canUnstage;
  final bool canDiscard;
  final VoidCallback onTap;
  final VoidCallback? onOpenFile;
  final VoidCallback onRevealInExplorer;
  final VoidCallback onStage;
  final VoidCallback onUnstage;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return _GitDiffBaseRow(
      depth: row.depth,
      onTap: onTap,
      onSecondaryTapDown: (details) =>
          unawaited(_openMenu(context, details.globalPosition)),
      onLongPressStart: (details) =>
          unawaited(_openMenu(context, details.globalPosition)),
      child: Row(
        children: <Widget>[
          Icon(
            collapsed ? AleraIcons.chevronRight : AleraIcons.chevronDown,
            size: 14,
            color: AleraTokens.foregroundMuted,
          ),
          const SizedBox(width: AleraTokens.space2),
          Expanded(
            child: _GitPathDragRegion(
              absolutePath: absolutePath,
              label: row.name,
              isDirectory: true,
              child: Row(
                children: <Widget>[
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
                ],
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

  Future<void> _openMenu(BuildContext context, Offset position) {
    return _showGitChangeContextMenu(
      context,
      position,
      canOpenFile: onOpenFile != null,
      canStage: canStage,
      canUnstage: canUnstage,
      canDiscard: canDiscard,
      busy: busy,
      onOpenFile: onOpenFile,
      onRevealInExplorer: onRevealInExplorer,
      onStage: onStage,
      onUnstage: onUnstage,
      onDiscard: onDiscard,
    );
  }
}

class _GitDiffFileRow extends StatelessWidget {
  const _GitDiffFileRow({
    required this.entry,
    required this.absolutePath,
    required this.depth,
    required this.onTap,
    required this.busy,
    this.onOpenFile,
    required this.onRevealInExplorer,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
    this.showRelativePath = false,
    this.showAreaMarker = false,
    this.submoduleExpanded = false,
    this.onToggleSubmodule,
  });

  final GitChangeEntry entry;
  final String absolutePath;
  final int depth;
  final VoidCallback onTap;
  final bool busy;
  final VoidCallback? onOpenFile;
  final VoidCallback onRevealInExplorer;
  final ValueChanged<GitChangeEntry> onStage;
  final ValueChanged<GitChangeEntry> onUnstage;
  final ValueChanged<GitChangeEntry> onDiscard;
  final bool showRelativePath;
  final bool showAreaMarker;
  final bool submoduleExpanded;
  final VoidCallback? onToggleSubmodule;

  @override
  Widget build(BuildContext context) {
    return _GitDiffBaseRow(
      depth: depth,
      onTap: onTap,
      onSecondaryTapDown: (details) =>
          unawaited(_openMenu(context, details.globalPosition)),
      onLongPressStart: (details) =>
          unawaited(_openMenu(context, details.globalPosition)),
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
          Expanded(
            child: _GitPathDragRegion(
              absolutePath: absolutePath,
              label: showRelativePath ? entry.path : entry.path.split('/').last,
              isDirectory: entry.submodule != null,
              child: Row(
                children: <Widget>[
                  AleraFileIcon(
                    pathOrName: entry.path,
                    kind: AleraFileIconKind.file,
                    size: 15,
                  ),
                  const SizedBox(width: AleraTokens.space6),
                  Expanded(
                    child: Text(
                      showRelativePath
                          ? entry.path
                          : entry.path.split('/').last,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (entry.isSubmoduleWorktreeOnly)
            Tooltip(
              message: 'Manage inside submodule',
              child: Text(
                'Inside',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AleraTokens.foregroundFaint,
                ),
              ),
            ),
          if (entry.isSubmoduleWorktreeOnly)
            const SizedBox(width: AleraTokens.space4),
          _GitStatusLabel(
            status: entry.status,
            area: entry.area,
            showAreaMarker: showAreaMarker,
          ),
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

  Future<void> _openMenu(BuildContext context, Offset position) {
    return _showGitChangeContextMenu(
      context,
      position,
      canOpenFile:
          onOpenFile != null && entry.status != GitChangeStatus.deleted,
      canStage: entry.canStageFromParent,
      canUnstage: entry.canUnstageFromParent,
      canDiscard: entry.canDiscardFromParent,
      busy: busy,
      onOpenFile: onOpenFile,
      onRevealInExplorer: onRevealInExplorer,
      onStage: () => onStage(entry),
      onUnstage: () => onUnstage(entry),
      onDiscard: () => onDiscard(entry),
    );
  }
}
