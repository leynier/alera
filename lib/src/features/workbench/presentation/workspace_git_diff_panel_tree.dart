part of 'workspace_git_diff_panel.dart';

class _GitDiffTree extends StatefulWidget {
  const _GitDiffTree({required this.entries, required this.onOpenGitDiff});

  final List<GitChangeEntry> entries;
  final OpenGitDiffTabCallback onOpenGitDiff;

  @override
  State<_GitDiffTree> createState() => _GitDiffTreeState();
}

class _GitDiffTreeState extends State<_GitDiffTree> {
  final Set<String> _collapsed = <String>{};

  @override
  Widget build(BuildContext context) {
    final roots = _buildTree(widget.entries);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[for (final node in roots) ..._buildNode(node)],
    );
  }

  List<Widget> _buildNode(_GitDiffTreeNode node) {
    if (node.entry case final entry?) {
      return <Widget>[
        _GitDiffFileRow(
          entry: entry,
          depth: node.depth,
          onTap: () => unawaited(
            widget.onOpenGitDiff(
              relativePath: entry.path,
              area: entry.area,
              scope: WorkspaceGitDiffScope.file,
            ),
          ),
        ),
      ];
    }
    final collapsed = _collapsed.contains(node.path);
    return <Widget>[
      _GitDiffDirectoryRow(
        node: node,
        collapsed: collapsed,
        onTap: () {
          setState(() {
            if (!_collapsed.add(node.path)) {
              _collapsed.remove(node.path);
            }
          });
        },
      ),
      if (!collapsed)
        for (final child in node.children) ..._buildNode(child),
    ];
  }

  List<_GitDiffTreeNode> _buildTree(List<GitChangeEntry> entries) {
    final root = _GitDiffTreeNode.directory(name: '', path: '', depth: -1);
    for (final entry in entries) {
      final parts = entry.path
          .split('/')
          .where((part) => part.isNotEmpty)
          .toList();
      if (parts.isEmpty) {
        continue;
      }
      var parent = root;
      for (var index = 0; index < parts.length - 1; index++) {
        final path = parts.take(index + 1).join('/');
        parent = parent.directoryChild(parts[index], path, index);
      }
      parent.children.add(
        _GitDiffTreeNode.file(
          name: parts.last,
          path: entry.path,
          depth: parts.length - 1,
          entry: entry,
        ),
      );
    }
    root.sortRecursively();
    return root.children;
  }
}

class _GitDiffTreeNode {
  _GitDiffTreeNode.directory({
    required this.name,
    required this.path,
    required this.depth,
  }) : entry = null;

  _GitDiffTreeNode.file({
    required this.name,
    required this.path,
    required this.depth,
    required this.entry,
  });

  final String name;
  final String path;
  final int depth;
  final GitChangeEntry? entry;
  final List<_GitDiffTreeNode> children = <_GitDiffTreeNode>[];

  _GitDiffTreeNode directoryChild(String name, String path, int depth) {
    for (final child in children) {
      if (child.entry == null && child.name == name) {
        return child;
      }
    }
    final child = _GitDiffTreeNode.directory(
      name: name,
      path: path,
      depth: depth,
    );
    children.add(child);
    return child;
  }

  void sortRecursively() {
    children.sort((a, b) {
      if (a.entry == null && b.entry != null) {
        return -1;
      }
      if (a.entry != null && b.entry == null) {
        return 1;
      }
      return a.name.compareTo(b.name);
    });
    for (final child in children) {
      child.sortRecursively();
    }
  }

  int get fileCount {
    if (entry != null) {
      return 1;
    }
    return children.fold<int>(0, (count, child) => count + child.fileCount);
  }
}

class _GitDiffDirectoryRow extends StatelessWidget {
  const _GitDiffDirectoryRow({
    required this.node,
    required this.collapsed,
    required this.onTap,
  });

  final _GitDiffTreeNode node;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _GitDiffBaseRow(
      depth: node.depth,
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Icon(
            collapsed ? Icons.chevron_right : Icons.expand_more,
            size: 14,
            color: AleraTokens.foregroundMuted,
          ),
          const SizedBox(width: AleraTokens.space2),
          AleraFileIcon(
            pathOrName: node.name,
            kind: AleraFileIconKind.folder,
            isExpanded: !collapsed,
            size: 15,
          ),
          const SizedBox(width: AleraTokens.space6),
          Expanded(
            child: Text(
              node.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ),
          Text(
            '${node.fileCount}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AleraTokens.foregroundFaint,
            ),
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
    this.showRelativePath = false,
  });

  final GitChangeEntry entry;
  final int depth;
  final VoidCallback onTap;
  final bool showRelativePath;

  @override
  Widget build(BuildContext context) {
    return _GitDiffBaseRow(
      depth: depth,
      onTap: onTap,
      child: Row(
        children: <Widget>[
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
          _GitStatusLabel(status: entry.status),
          const SizedBox(width: AleraTokens.space6),
          _LineStats(added: entry.added, removed: entry.removed),
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
