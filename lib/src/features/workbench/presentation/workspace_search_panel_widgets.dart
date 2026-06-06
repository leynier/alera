part of 'workspace_search_panel.dart';

class _SearchToggleButton extends StatelessWidget {
  const _SearchToggleButton({
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
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

class _SearchSummary extends StatelessWidget {
  const _SearchSummary({required this.state});

  final WorkspaceSearchState state;

  @override
  Widget build(BuildContext context) {
    final result = state.result;
    final text = !state.hasQuery
        ? 'Enter a search query'
        : state.loading
        ? 'Searching...'
        : result == null
        ? 'No results'
        : _resultSummary(result);
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (state.replacing)
            const SizedBox.square(
              dimension: AleraTokens.space16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  String _resultSummary(native.WorkspaceSearchResult result) {
    final suffix = result.truncated ? ' shown' : '';
    final matchWord = result.totalMatches == 1 ? 'match' : 'matches';
    final fileWord = result.files.length == 1 ? 'file' : 'files';
    return '${result.totalMatches} $matchWord in ${result.files.length} $fileWord$suffix';
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({required this.state});

  final WorkspaceSearchState state;

  @override
  Widget build(BuildContext context) {
    if (state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final message = state.hasQuery ? 'No results' : 'Search this workspace';
    return Center(
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AleraTokens.foregroundMuted),
      ),
    );
  }
}

class _SearchFileResultRow extends StatelessWidget {
  const _SearchFileResultRow({
    required this.file,
    required this.collapsed,
    required this.replacing,
    required this.onToggleCollapsed,
    required this.onReplaceFile,
  });

  final native.WorkspaceSearchFileResult file;
  final bool collapsed;
  final bool replacing;
  final VoidCallback onToggleCollapsed;
  final VoidCallback? onReplaceFile;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggleCollapsed,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space8,
          vertical: AleraTokens.space6,
        ),
        child: Row(
          children: <Widget>[
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 16,
              color: AleraTokens.foregroundMuted,
            ),
            const SizedBox(width: AleraTokens.space4),
            Expanded(
              child: Text(
                file.relativePath,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foreground,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${file.matches.length}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            const SizedBox(width: AleraTokens.space4),
            AleraIconButton(
              tooltip: 'Replace in file',
              icon: Icons.find_replace,
              onPressed: replacing ? null : onReplaceFile,
              minSize: AleraTokens.space24,
              iconSize: 14,
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchMatchResultRow extends StatelessWidget {
  const _SearchMatchResultRow({
    required this.file,
    required this.match,
    required this.replacing,
    required this.onOpen,
    required this.onReplace,
  });

  final native.WorkspaceSearchFileResult file;
  final native.WorkspaceSearchMatch match;
  final bool replacing;
  final VoidCallback onOpen;
  final VoidCallback? onReplace;

  @override
  Widget build(BuildContext context) {
    final preview = match.replacementPreview;
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AleraTokens.space32,
          AleraTokens.space4,
          AleraTokens.space8,
          AleraTokens.space6,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: AleraTokens.space32,
              child: Text(
                '${match.line}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundFaint,
                  fontFamily: 'JetBrains Mono',
                ),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    match.lineContent.trimRight(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                      fontFamily: 'JetBrains Mono',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (preview != null)
                    Text(
                      preview.trimRight(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AleraTokens.success,
                        fontFamily: 'JetBrains Mono',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: AleraTokens.space4),
            AleraIconButton(
              tooltip: 'Replace match',
              icon: Icons.find_replace,
              onPressed: replacing ? null : onReplace,
              minSize: AleraTokens.space24,
              iconSize: 14,
            ),
          ],
        ),
      ),
    );
  }
}
