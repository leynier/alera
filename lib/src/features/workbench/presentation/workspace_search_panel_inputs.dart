part of 'workspace_search_panel.dart';

const double _searchInlineButtonSize = AleraTokens.space24;

class _WorkspaceSearchInputs extends StatelessWidget {
  const _WorkspaceSearchInputs({
    required this.queryController,
    required this.replacementController,
    required this.includeController,
    required this.excludeController,
    required this.state,
    required this.replaceVisible,
    required this.detailsVisible,
    required this.canReplaceAll,
    required this.onToggleReplace,
    required this.onToggleDetails,
    required this.onQueryChanged,
    required this.onQuerySubmitted,
    required this.onReplacementChanged,
    required this.onIncludeChanged,
    required this.onExcludeChanged,
    required this.onToggleCaseSensitive,
    required this.onToggleWholeWord,
    required this.onToggleUseRegex,
    required this.onTogglePreserveCase,
    required this.onReplaceAll,
  });

  final TextEditingController queryController;
  final TextEditingController replacementController;
  final TextEditingController includeController;
  final TextEditingController excludeController;
  final WorkspaceSearchState state;
  final bool replaceVisible;
  final bool detailsVisible;
  final bool canReplaceAll;
  final VoidCallback onToggleReplace;
  final VoidCallback onToggleDetails;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String> onQuerySubmitted;
  final ValueChanged<String> onReplacementChanged;
  final ValueChanged<String> onIncludeChanged;
  final ValueChanged<String> onExcludeChanged;
  final VoidCallback onToggleCaseSensitive;
  final VoidCallback onToggleWholeWord;
  final VoidCallback onToggleUseRegex;
  final VoidCallback onTogglePreserveCase;
  final VoidCallback onReplaceAll;

  @override
  Widget build(BuildContext context) {
    final detailsActive =
        detailsVisible ||
        state.includePattern.isNotEmpty ||
        state.excludePattern.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            _SearchChevronButton(
              expanded: replaceVisible,
              onPressed: onToggleReplace,
            ),
            const SizedBox(width: AleraTokens.space2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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

class _SearchDetailField extends StatelessWidget {
  const _SearchDetailField({
    required this.hintText,
    required this.controller,
    required this.icon,
    required this.onChanged,
  });

  final String hintText;
  final TextEditingController controller;
  final IconData icon;
  final ValueChanged<String> onChanged;

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

class _SearchInputActions extends StatelessWidget {
  const _SearchInputActions({required this.children});

  final List<Widget> children;

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
      child: Row(mainAxisSize: MainAxisSize.min, children: spacedChildren),
    );
  }
}

class _SearchChevronButton extends StatelessWidget {
  const _SearchChevronButton({required this.expanded, required this.onPressed});

  final bool expanded;
  final VoidCallback onPressed;

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

class _SearchInlineToggleButton extends StatelessWidget {
  const _SearchInlineToggleButton({
    required this.tooltip,
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final String tooltip;
  final String label;
  final bool active;
  final VoidCallback? onPressed;

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

class _SearchInlineIconButton extends StatelessWidget {
  const _SearchInlineIconButton({
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool active;
  final VoidCallback? onPressed;

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

class _SearchInlineButtonFrame extends StatelessWidget {
  const _SearchInlineButtonFrame({
    required this.tooltip,
    required this.active,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final bool active;
  final VoidCallback? onPressed;
  final Widget child;

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
