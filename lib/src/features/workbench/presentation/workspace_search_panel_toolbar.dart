part of 'workspace_search_panel.dart';

class const _SearchToolbar({
  required final WorkspaceSearchState state,
  required final bool allResultsCollapsed,
  required final VoidCallback onRefresh,
  required final VoidCallback onClear,
  required final VoidCallback onToggleIncludeIgnored,
  required final VoidCallback onToggleViewAsTree,
  required final VoidCallback onToggleAllResultsCollapsed,
}) extends StatelessWidget {
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
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: AleraTokens.foreground, fontWeight: .w600),
            ),
            const Spacer(),
            AleraIconButton(
              tooltip: 'Clear search results',
              icon: AleraIcons.close,
              onPressed: canClear ? onClear : null,
            ),
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: state.includeIgnored
                  ? 'Ignore ignored files'
                  : 'Search ignored files',
              icon: state.includeIgnored
                  ? AleraIcons.visible
                  : AleraIcons.hidden,
              onPressed: onToggleIncludeIgnored,
              iconColor: state.includeIgnored
                  ? AleraTokens.foreground
                  : AleraTokens.foregroundMuted,
              backgroundColor: state.includeIgnored
                  ? AleraTokens.surfaceElevated
                  : null,
              borderColor: state.includeIgnored ? AleraTokens.border : null,
            ),
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: state.viewAsTree ? 'View as list' : 'View as tree',
              icon: state.viewAsTree
                  ? AleraIcons.listView
                  : AleraIcons.gitGraph,
              onPressed: onToggleViewAsTree,
            ),
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: allResultsCollapsed ? 'Expand All' : 'Collapse All',
              icon: allResultsCollapsed
                  ? AleraIcons.expandAll
                  : AleraIcons.collapseAll,
              onPressed: hasResults ? onToggleAllResultsCollapsed : null,
            ),
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: 'Refresh',
              icon: state.loading ? AleraIcons.loading : AleraIcons.refresh,
              onPressed: state.hasQuery && !state.loading ? onRefresh : null,
            ),
          ],
        ),
      ),
    );
  }
}
