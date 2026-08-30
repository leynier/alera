part of 'workspace_search_panel.dart';

const double _searchInlineButtonSize = AleraTokens.space24;

class const _WorkspaceSearchInputs({
  required final TextEditingController queryController,
  required final TextEditingController replacementController,
  required final TextEditingController includeController,
  required final TextEditingController excludeController,
  required final WorkspaceSearchState state,
  required final bool replaceVisible,
  required final bool detailsVisible,
  required final bool canReplaceAll,
  required final VoidCallback onToggleReplace,
  required final VoidCallback onToggleDetails,
  required final ValueChanged<String> onQueryChanged,
  required final ValueChanged<String> onQuerySubmitted,
  required final ValueChanged<String> onReplacementChanged,
  required final ValueChanged<String> onIncludeChanged,
  required final ValueChanged<String> onExcludeChanged,
  required final VoidCallback onToggleCaseSensitive,
  required final VoidCallback onToggleWholeWord,
  required final VoidCallback onToggleUseRegex,
  required final VoidCallback onTogglePreserveCase,
  required final VoidCallback onReplaceAll,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final detailsActive =
        detailsVisible ||
        state.includePattern.isNotEmpty ||
        state.excludePattern.isNotEmpty;
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: .center,
          children: <Widget>[
            _SearchChevronButton(
              expanded: replaceVisible,
              onPressed: onToggleReplace,
            ),
            const SizedBox(width: AleraTokens.space2),
            Expanded(
              child: Column(
                crossAxisAlignment: .stretch,
                children: <Widget>[
                  AleraTextField(
                    controller: queryController,
                    dense: true,
                    autofocus: true,
                    hintText: 'Search',
                    suffix: _SearchInputActions(
                      children: <Widget>[
                        _SearchInlineToggleButton(
                          tooltip: 'Match case',
                          label: 'Aa',
                          active: state.caseSensitive,
                          onPressed: onToggleCaseSensitive,
                        ),
                        _SearchInlineToggleButton(
                          tooltip: 'Match whole word',
                          label: 'ab',
                          active: state.wholeWord,
                          onPressed: onToggleWholeWord,
                        ),
                        _SearchInlineToggleButton(
                          tooltip: 'Use regular expression',
                          label: '.*',
                          active: state.useRegex,
                          onPressed: onToggleUseRegex,
                        ),
                      ],
                    ),
                    onChanged: onQueryChanged,
                    onSubmitted: onQuerySubmitted,
                  ),
                  if (replaceVisible) ...<Widget>[
                    const SizedBox(height: AleraTokens.space4),
                    AleraTextField(
                      controller: replacementController,
                      dense: true,
                      hintText: 'Replace',
                      suffix: _SearchInputActions(
                        children: <Widget>[
                          _SearchInlineToggleButton(
                            tooltip: 'Preserve case',
                            label: 'AB',
                            active: state.preserveCase,
                            onPressed: onTogglePreserveCase,
                          ),
                          _SearchInlineIconButton(
                            tooltip: 'Replace all',
                            icon: AleraIcons.doneAll,
                            active: false,
                            onPressed: canReplaceAll ? onReplaceAll : null,
                          ),
                        ],
                      ),
                      onChanged: onReplacementChanged,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: _SearchInlineIconButton(
            tooltip: detailsVisible ? 'Hide details' : 'Show details',
            icon: AleraIcons.more,
            active: detailsActive,
            onPressed: onToggleDetails,
          ),
        ),
        if (detailsVisible) ...<Widget>[
          _SearchDetailField(
            hintText: 'Files to include',
            controller: includeController,
            icon: AleraIcons.gridView,
            onChanged: onIncludeChanged,
          ),
          const SizedBox(height: AleraTokens.space6),
          _SearchDetailField(
            hintText: 'Files to exclude',
            controller: excludeController,
            icon: AleraIcons.searchManage,
            onChanged: onExcludeChanged,
          ),
        ],
      ],
    );
  }
}

class const _SearchDetailField({
  required final String hintText,
  required final TextEditingController controller,
  required final IconData icon,
  required final ValueChanged<String> onChanged,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AleraTextField(
      controller: controller,
      dense: true,
      hintText: hintText,
      suffix: _SearchInputActions(
        children: <Widget>[
          _SearchInlineIconButton(
            tooltip: hintText,
            icon: icon,
            active: false,
            onPressed: null,
          ),
        ],
      ),
      onChanged: onChanged,
    );
  }
}

class const _SearchInputActions({required final List<Widget> children})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final spacedChildren = <Widget>[];
    for (final child in children) {
      if (spacedChildren.isNotEmpty) {
        spacedChildren.add(const SizedBox(width: AleraTokens.space2));
      }
      spacedChildren.add(child);
    }
    return Padding(
      padding: const EdgeInsets.only(right: AleraTokens.space4),
      child: Row(mainAxisSize: .min, children: spacedChildren),
    );
  }
}

class const _SearchChevronButton({
  required final bool expanded,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: expanded ? 'Hide replace' : 'Show replace',
      child: InkResponse(
        onTap: onPressed,
        mouseCursor: SystemMouseCursors.click,
        radius: _searchInlineButtonSize / 2,
        child: SizedBox.square(
          dimension: AleraTokens.space16,
          child: Icon(
            expanded ? AleraIcons.chevronDown : AleraIcons.chevronRight,
            size: 16,
            color: AleraTokens.foregroundMuted,
          ),
        ),
      ),
    );
  }
}

class const _SearchInlineToggleButton({
  required final String tooltip,
  required final String label,
  required final bool active,
  required final VoidCallback? onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: active ? AleraTokens.foreground : AleraTokens.foregroundMuted,
      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
    );
    return _SearchInlineButtonFrame(
      tooltip: tooltip,
      active: active,
      onPressed: onPressed,
      child: Text(label, style: style),
    );
  }
}

class const _SearchInlineIconButton({
  required final String tooltip,
  required final IconData icon,
  required final bool active,
  required final VoidCallback? onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _SearchInlineButtonFrame(
      tooltip: tooltip,
      active: active,
      onPressed: onPressed,
      child: Icon(
        icon,
        size: 14,
        color: active ? AleraTokens.foreground : AleraTokens.foregroundMuted,
      ),
    );
  }
}

class const _SearchInlineButtonFrame({
  required final String tooltip,
  required final bool active,
  required final VoidCallback? onPressed,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onPressed,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        radius: _searchInlineButtonSize / 2,
        child: AnimatedContainer(
          duration: AleraTokens.durationFast,
          width: _searchInlineButtonSize,
          height: _searchInlineButtonSize,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AleraTokens.surfaceElevated : Colors.transparent,
            borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
            border: active ? Border.all(color: AleraTokens.border) : null,
          ),
          child: Opacity(opacity: enabled ? 1 : 0.45, child: child),
        ),
      ),
    );
  }
}
