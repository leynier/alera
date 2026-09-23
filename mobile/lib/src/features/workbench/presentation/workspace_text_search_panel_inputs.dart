part of 'workspace_text_search_panel.dart';

/// Query, replace, and file filters. The desktop toolbar's icon row does not
/// fit a phone, so only Refresh and Clear stay visible and the view toggles
/// move to a sheet behind one button.
class const _SearchInputs({
  required final WorkspaceTextSearchState state,
  required final TextEditingController query,
  required final TextEditingController replacement,
  required final TextEditingController include,
  required final TextEditingController exclude,
  required final bool canReplace,
  required final bool replaceVisible,
  required final bool filtersVisible,
  required final WorkspaceTextSearchController notifier,
  required final VoidCallback onToggleReplace,
  required final VoidCallback onToggleFilters,
  required final VoidCallback onShowViewOptions,
  required final VoidCallback? onReplaceAll,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final canClear =
        state.query.isNotEmpty ||
        state.replacement.isNotEmpty ||
        state.includePattern.isNotEmpty ||
        state.excludePattern.isNotEmpty ||
        state.result != null ||
        state.error != null;
    return Padding(
      padding: AleraTokens.contentPadding,
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          AleraSearchField(
            controller: query,
            hintText: 'Search',
            autofocus: true,
            onChanged: notifier.setQuery,
          ),
          const SizedBox(height: AleraTokens.space8),
          Row(
            children: <Widget>[
              _Toggle(
                label: 'Aa',
                tooltip: 'Match Case',
                active: state.caseSensitive,
                onPressed: notifier.toggleCaseSensitive,
              ),
              _Toggle(
                label: 'ab',
                tooltip: 'Match Whole Word',
                active: state.wholeWord,
                onPressed: notifier.toggleWholeWord,
              ),
              _Toggle(
                label: '.*',
                tooltip: 'Use Regular Expression',
                active: state.useRegex,
                onPressed: notifier.toggleUseRegex,
              ),
              const Spacer(),
              AleraIconButton(
                tooltip: 'Refresh',
                icon: AleraIcons.refresh,
                onPressed: state.hasQuery && !state.searching
                    ? () => unawaited(notifier.runNow())
                    : null,
              ),
              AleraIconButton(
                tooltip: 'Clear',
                icon: AleraIcons.close,
                onPressed: canClear ? notifier.clear : null,
              ),
              AleraIconButton(
                tooltip: 'View Options',
                icon: AleraIcons.tune,
                onPressed: onShowViewOptions,
              ),
            ],
          ),
          Row(
            children: <Widget>[
              if (canReplace)
                TextButton.icon(
                  onPressed: onToggleReplace,
                  icon: Icon(
                    replaceVisible
                        ? AleraIcons.chevronDown
                        : AleraIcons.chevronRight,
                    size: 16,
                  ),
                  label: const Text('Replace'),
                ),
              TextButton.icon(
                onPressed: onToggleFilters,
                icon: Icon(
                  filtersVisible
                      ? AleraIcons.chevronDown
                      : AleraIcons.chevronRight,
                  size: 16,
                ),
                label: const Text('Files'),
              ),
            ],
          ),
          if (replaceVisible) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: AleraTextField(
                    controller: replacement,
                    hintText: 'Replace',
                    onChanged: notifier.setReplacement,
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                _Toggle(
                  label: 'AB',
                  tooltip: 'Preserve Case',
                  active: state.preserveCase,
                  onPressed: notifier.togglePreserveCase,
                ),
                AleraIconButton(
                  tooltip: 'Replace All',
                  icon: AleraIcons.replaceAll,
                  onPressed: onReplaceAll,
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space8),
          ],
          if (filtersVisible) ...<Widget>[
            AleraTextField(
              controller: include,
              hintText: 'Files to include',
              onChanged: notifier.setIncludePattern,
            ),
            const SizedBox(height: AleraTokens.space8),
            AleraTextField(
              controller: exclude,
              hintText: 'Files to exclude',
              onChanged: notifier.setExcludePattern,
            ),
          ],
        ],
      ),
    );
  }
}

class const _Toggle({
  required final String label,
  required final String tooltip,
  required final bool active,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AleraTokens.space8),
      child: Tooltip(
        message: tooltip,
        child: FilterChip(
          label: Text(label),
          selected: active,
          onSelected: (_) => onPressed(),
        ),
      ),
    );
  }
}
