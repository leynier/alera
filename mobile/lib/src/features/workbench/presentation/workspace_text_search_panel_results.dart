part of 'workspace_text_search_panel.dart';

class const _Results({
  required final WorkspaceTextSearchState state,
  required final bool replaceVisible,
  required final WorkspaceTextSearchController notifier,
  required final void Function(
    MobileWorkspaceSearchFile file,
    MobileWorkspaceSearchMatch match,
  )
  onOpenMatch,
  required final ValueChanged<Iterable<String>> onReplace,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (state.error case final error?) {
      return AleraEmptyState(
        icon: AleraIcons.search,
        message: error is UnsupportedError
            ? error.message ?? '$error'
            : error.toString(),
      );
    }
    if (!state.hasQuery) {
      return const AleraEmptyState(
        icon: AleraIcons.search,
        title: 'Search',
        message: 'Type to search the workspace.',
      );
    }
    final result = state.result;
    if (result == null) {
      return const SizedBox.shrink();
    }
    if (result.files.isEmpty) {
      return const AleraEmptyState(
        icon: AleraIcons.search,
        title: 'No matches',
        message: 'Nothing in this workspace matched the query.',
      );
    }
    final rows = workspaceSearchRows(
      result,
      collapsedNodeKeys: state.collapsedResultNodeKeys,
      viewAsTree: state.viewAsTree,
    );
    final canReplace = replaceVisible && state.canReplace;
    final canReplaceFile = replaceVisible && state.canReplaceAll;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AleraTokens.space16,
            0,
            AleraTokens.space16,
            AleraTokens.space4,
          ),
          child: Text(
            '${_count(result.totalMatches, 'match', 'matches')} in ${_count(result.files.length, 'file', 'files')}${result.truncated ? ' (truncated)' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, index) => switch (rows[index]) {
              WorkspaceSearchDirectoryRow(
                :final name,
                :final path,
                :final depth,
                :final matchCount,
              ) =>
                _NodeRow(
                  depth: depth,
                  collapsed: state.collapsedResultNodeKeys.contains(
                    workspaceSearchDirectoryNodeKey(path),
                  ),
                  leading: AleraFileIcon(
                    pathOrName: name,
                    kind: .folder,
                    isExpanded: !state.collapsedResultNodeKeys.contains(
                      workspaceSearchDirectoryNodeKey(path),
                    ),
                  ),
                  title: name,
                  count: matchCount,
                  onToggle: () => notifier.toggleResultNodeCollapsed(
                    workspaceSearchDirectoryNodeKey(path),
                  ),
                ),
              WorkspaceSearchFileRow(:final file, :final depth) => _NodeRow(
                depth: depth,
                collapsed: state.collapsedResultNodeKeys.contains(
                  workspaceSearchFileNodeKey(file.relativePath),
                ),
                leading: AleraFileIcon(
                  pathOrName: file.relativePath,
                  kind: .file,
                ),
                title: workspaceFileBaseName(file.relativePath),
                subtitle: state.viewAsTree
                    ? null
                    : workspaceFileParentLabel(file.relativePath),
                count: file.matches.length,
                onToggle: () => notifier.toggleResultNodeCollapsed(
                  workspaceSearchFileNodeKey(file.relativePath),
                ),
                onReplace: canReplaceFile
                    ? () => onReplace(file.matches.map((match) => match.id))
                    : null,
                replaceTooltip: 'Replace in File',
              ),
              WorkspaceSearchMatchRow(
                :final file,
                :final match,
                :final depth,
              ) =>
                _MatchRow(
                  match: match,
                  depth: depth,
                  showPreview: replaceVisible,
                  onOpen: () => onOpenMatch(file, match),
                  onReplace: canReplace
                      ? () => onReplace(<String>[match.id])
                      : null,
                ),
            },
          ),
        ),
      ],
    );
  }
}

EdgeInsets _rowPadding(int depth) => EdgeInsets.only(
  left: AleraTokens.space8 + depth * AleraTokens.space16,
  right: AleraTokens.space4,
);

class const _NodeRow({
  required final int depth,
  required final bool collapsed,
  required final Widget leading,
  required final String title,
  final String? subtitle,
  required final int count,
  required final VoidCallback onToggle,
  final VoidCallback? onReplace,
  final String replaceTooltip = '',
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onToggle,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AleraTokens.minTapTarget),
        child: Padding(
          padding: _rowPadding(depth),
          child: Row(
            children: <Widget>[
              Icon(
                collapsed ? AleraIcons.chevronRight : AleraIcons.chevronDown,
                size: 16,
                color: AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space4),
              leading,
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  mainAxisSize: .min,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (subtitle case final subtitle?)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              Text(
                '$count',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AleraTokens.foregroundFaint,
                ),
              ),
              if (onReplace != null)
                AleraIconButton(
                  tooltip: replaceTooltip,
                  icon: AleraIcons.findReplace,
                  onPressed: onReplace,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class const _MatchRow({
  required final MobileWorkspaceSearchMatch match,
  required final int depth,
  required final bool showPreview,
  required final VoidCallback onOpen,
  required final VoidCallback? onReplace,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final base = (Theme.of(context).textTheme.bodySmall ?? const TextStyle())
        .merge(AleraTokens.monoStyle)
        .copyWith(color: AleraTokens.foregroundMuted);
    final text = match.lineContent.trimRight();
    final range = workspaceSearchMatchRange(match, text);
    final preview = match.replacementPreview;
    final matched = text.substring(range.start, range.end);
    final middle = showPreview && preview != null
        ? <InlineSpan>[
            TextSpan(
              text: matched,
              style: base.copyWith(
                color: AleraTokens.error,
                backgroundColor: AleraTokens.onError,
                decoration: .lineThrough,
                decorationColor: AleraTokens.error,
              ),
            ),
            TextSpan(
              text: preview,
              style: base.copyWith(
                color: AleraTokens.success,
                fontWeight: .w700,
              ),
            ),
          ]
        : <InlineSpan>[
            TextSpan(
              text: matched,
              style: base.copyWith(
                color: AleraTokens.foreground,
                backgroundColor: AleraTokens.accentSubtle,
                fontWeight: .w700,
              ),
            ),
          ];
    return InkWell(
      onTap: onOpen,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AleraTokens.minTapTarget),
        child: Padding(
          padding: _rowPadding(depth),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: AleraTokens.space32,
                child: Text(
                  '${match.line}',
                  textAlign: .right,
                  style: base.copyWith(color: AleraTokens.foregroundFaint),
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: text.substring(0, range.start),
                        style: base,
                      ),
                      ...middle,
                      TextSpan(text: text.substring(range.end), style: base),
                    ],
                  ),
                  maxLines: 2,
                  overflow: .ellipsis,
                ),
              ),
              if (onReplace != null)
                AleraIconButton(
                  tooltip: 'Replace Match',
                  icon: AleraIcons.findReplace,
                  onPressed: onReplace,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
