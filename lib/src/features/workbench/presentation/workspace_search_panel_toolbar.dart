part of 'workspace_search_panel.dart';

class _SearchToolbar extends StatelessWidget {
  const _SearchToolbar({
    required this.state,
    required this.allResultsCollapsed,
    required this.onRefresh,
    required this.onClear,
    required this.onToggleViewAsTree,
    required this.onToggleAllResultsCollapsed,
  });

  final WorkspaceSearchState state;
  final bool allResultsCollapsed;
  final VoidCallback onRefresh;
  final VoidCallback onClear;
  final VoidCallback onToggleViewAsTree;
  final VoidCallback onToggleAllResultsCollapsed;

  @override
  Widget build(BuildContext context) {
    final hasResults = state.result?.files.isNotEmpty ?? false;
    final canClear =
        state.query.isNotEmpty ||
        state.replacement.isNotEmpty ||
        state.includePattern.isNotEmpty ||
        state.excludePattern.isNotEmpty ||
        state.result != null ||
        state.error != null ||
        state.loading;
    return SizedBox(
      height: AleraTokens.sidebarHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
        child: Row(
          children: <Widget>[
            Text(
              'Search',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AleraTokens.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            AleraIconButton(
              tooltip: 'Refresh',
              icon: state.loading ? Icons.hourglass_empty : Icons.refresh,
              onPressed: state.hasQuery && !state.loading ? onRefresh : null,
            ),
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: 'Clear search results',
              icon: Icons.close,
              onPressed: canClear ? onClear : null,
            ),
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: state.viewAsTree ? 'View as list' : 'View as tree',
              icon: state.viewAsTree
                  ? Icons.account_tree
                  : Icons.account_tree_outlined,
              onPressed: onToggleViewAsTree,
              iconColor: state.viewAsTree
                  ? AleraTokens.foreground
                  : AleraTokens.foregroundMuted,
              backgroundColor: state.viewAsTree
                  ? AleraTokens.surfaceElevated
                  : null,
              borderColor: state.viewAsTree ? AleraTokens.border : null,
            ),
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: allResultsCollapsed ? 'Expand all' : 'Collapse all',
              icon: allResultsCollapsed ? Icons.unfold_more : Icons.unfold_less,
              onPressed: hasResults ? onToggleAllResultsCollapsed : null,
            ),
          ],
        ),
      ),
    );
  }
}
