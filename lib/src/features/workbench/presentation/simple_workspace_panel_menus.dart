part of 'simple_workspace_panel_view.dart';

enum _SimpleToolMenuAction {
  splitUp,
  splitDown,
  splitLeft,
  splitRight,
  close,
  closeOthers,
  closeRight,
}

enum _SimplePaneMenuAction {
  splitRight,
  splitDown,
  splitLeft,
  splitUp,
  closeSplit,
}

class const _SimplePaneMenuButton({
  required final bool canCloseSplit,
  required final ValueChanged<WorkbenchDropZone> onSplitGroup,
  required final VoidCallback onMergeGroup,
}) extends StatelessWidget {
  Future<void> _openMenu(BuildContext context) async {
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final topLeft = button.localToGlobal(
      button.size.bottomLeft(.zero),
      ancestor: overlay,
    );
    final bottomRight = button.localToGlobal(
      button.size.bottomRight(.zero),
      ancestor: overlay,
    );
    final selected = await showMenu<_SimplePaneMenuAction>(
      context: context,
      position: .fromRect(
        .fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<_SimplePaneMenuAction>>[
        const AleraDropdownEntry(
          value: .splitRight,
          label: 'Split Right',
          leading: WorkbenchSplitDirectionGlyph(zone: .right),
        ),
        const AleraDropdownEntry(
          value: .splitDown,
          label: 'Split Down',
          leading: WorkbenchSplitDirectionGlyph(zone: .down),
        ),
        const AleraDropdownEntry(
          value: .splitLeft,
          label: 'Split Left',
          leading: WorkbenchSplitDirectionGlyph(zone: .left),
        ),
        const AleraDropdownEntry(
          value: .splitUp,
          label: 'Split Up',
          leading: WorkbenchSplitDirectionGlyph(zone: .up),
        ),
        if (canCloseSplit) const PopupMenuDivider(height: AleraTokens.space8),
        if (canCloseSplit)
          const AleraDropdownEntry(value: .closeSplit, label: 'Close Split'),
      ],
    );
    if (selected == null) {
      return;
    }
    switch (selected) {
      case _SimplePaneMenuAction.splitRight:
        onSplitGroup(.right);
      case _SimplePaneMenuAction.splitDown:
        onSplitGroup(.down);
      case _SimplePaneMenuAction.splitLeft:
        onSplitGroup(.left);
      case _SimplePaneMenuAction.splitUp:
        onSplitGroup(.up);
      case _SimplePaneMenuAction.closeSplit:
        onMergeGroup();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AleraIconButton(
      tooltip: 'Pane Actions',
      onPressed: () => unawaited(_openMenu(context)),
      icon: AleraIcons.more,
      minSize: 28,
    );
  }
}

class const _SimplePanelToolChip({
  required final String label,
  required final IconData icon,
  required final bool active,
  required final List<String> groupKeys,
  required final String tabKey,
  required final VoidCallback onSelect,
  required final VoidCallback onClose,
  required final ValueChanged<List<String>> onCloseKeys,
  final ValueChanged<WorkbenchDropZone>? onSplit,
}) extends StatelessWidget {
  Future<void> _openMenu(BuildContext context, Offset globalPosition) async {
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final tabIndex = groupKeys.indexOf(tabKey);
    final closeOthers = <String>[
      for (final key in groupKeys)
        if (key != tabKey) key,
    ];
    final closeRight = tabIndex < 0
        ? const <String>[]
        : groupKeys.skip(tabIndex + 1).toList();
    final selected = await showMenu<_SimpleToolMenuAction>(
      context: context,
      position: .fromRect(
        .fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<_SimpleToolMenuAction>>[
        if (onSplit != null) ...<PopupMenuEntry<_SimpleToolMenuAction>>[
          const AleraDropdownEntry(
            value: .splitUp,
            label: 'Split Up',
            leading: WorkbenchSplitDirectionGlyph(zone: .up),
          ),
          const AleraDropdownEntry(
            value: .splitDown,
            label: 'Split Down',
            leading: WorkbenchSplitDirectionGlyph(zone: .down),
          ),
          const AleraDropdownEntry(
            value: .splitLeft,
            label: 'Split Left',
            leading: WorkbenchSplitDirectionGlyph(zone: .left),
          ),
          const AleraDropdownEntry(
            value: .splitRight,
            label: 'Split Right',
            leading: WorkbenchSplitDirectionGlyph(zone: .right),
          ),
          const PopupMenuDivider(height: AleraTokens.space8),
        ],
        const AleraDropdownEntry(
          value: .close,
          label: 'Close',
          leading: Icon(AleraIcons.close, size: 16),
        ),
        AleraDropdownEntry(
          value: .closeOthers,
          label: 'Close Others',
          leading: Icon(
            AleraIcons.tabUnselected,
            size: 16,
            color: closeOthers.isEmpty
                ? AleraTokens.foregroundFaint
                : AleraTokens.foreground,
          ),
          enabled: closeOthers.isNotEmpty,
        ),
        AleraDropdownEntry(
          value: .closeRight,
          label: 'Close Tabs to the Right',
          leading: Icon(
            AleraIcons.tab,
            size: 16,
            color: closeRight.isEmpty
                ? AleraTokens.foregroundFaint
                : AleraTokens.foreground,
          ),
          enabled: closeRight.isNotEmpty,
        ),
      ],
    );
    if (selected == null) {
      return;
    }
    switch (selected) {
      case _SimpleToolMenuAction.splitUp:
        onSplit?.call(.up);
      case _SimpleToolMenuAction.splitDown:
        onSplit?.call(.down);
      case _SimpleToolMenuAction.splitLeft:
        onSplit?.call(.left);
      case _SimpleToolMenuAction.splitRight:
        onSplit?.call(.right);
      case _SimpleToolMenuAction.close:
        onClose();
      case _SimpleToolMenuAction.closeOthers:
        onCloseKeys(closeOthers);
      case _SimpleToolMenuAction.closeRight:
        onCloseKeys(closeRight);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = active ? AleraTokens.foreground : AleraTokens.foregroundMuted;
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          unawaited(_openMenu(context, details.globalPosition)),
      child: Material(
        color: active ? AleraTokens.surfaceElevated : AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        child: InkWell(
          onTap: onSelect,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: .circular(AleraTokens.radiusMd),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space6,
              vertical: AleraTokens.space6,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
              border: Border.all(
                color: active ? AleraTokens.border : AleraTokens.borderSubtle,
              ),
            ),
            child: Row(
              mainAxisSize: .min,
              children: <Widget>[
                Icon(icon, size: 12, color: color),
                const SizedBox(width: AleraTokens.space4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 92),
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: .ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: color),
                  ),
                ),
                const SizedBox(width: AleraTokens.space4),
                InkWell(
                  onTap: onClose,
                  mouseCursor: SystemMouseCursors.click,
                  borderRadius: .circular(AleraTokens.radiusSm),
                  child: Tooltip(
                    message: 'Close $label',
                    child: const Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(
                        AleraIcons.close,
                        size: 12,
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class const _SimplePanelAddButton({
  required final List<SimpleWorkspaceTool> availableTools,
  required final ValueChanged<String> onSelect,
  required final VoidCallback onNewTerminal,
}) extends StatelessWidget {
  Future<void> _openMenu(BuildContext context) async {
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final topLeft = button.localToGlobal(
      button.size.bottomLeft(.zero),
      ancestor: overlay,
    );
    final bottomRight = button.localToGlobal(
      button.size.bottomRight(.zero),
      ancestor: overlay,
    );
    final selected = await showMenu<String>(
      context: context,
      position: .fromRect(
        .fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<String>>[
        for (final tool in availableTools)
          AleraDropdownEntry(value: tool.key, label: tool.label),
        const AleraDropdownEntry(value: 'terminal', label: 'Terminal'),
      ],
    );
    if (selected == null) {
      return;
    }
    if (selected == 'terminal') {
      onNewTerminal();
      return;
    }
    onSelect(selected);
  }

  @override
  Widget build(BuildContext context) {
    return AleraIconButton(
      tooltip: 'Add Tab',
      icon: AleraIcons.add,
      iconSize: 16,
      minSize: 28,
      hoverColor: AleraTokens.surfaceElevated,
      borderRadius: AleraTokens.radiusSm,
      onPressed: () => unawaited(_openMenu(context)),
    );
  }
}

class const _SimpleStripChipDropTarget({
  required final int chipIndex,
  required final String workspaceId,
  required final bool showLeadingIndicator,
  required final bool showTrailingIndicator,
  required final void Function(SimplePaneTabDragData data, int gapIndex)
  onHoverGap,
  required final VoidCallback onLeave,
  required final void Function(SimplePaneTabDragData data, int gapIndex)
  onDropGap,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DragTarget<SimplePaneTabDragData>(
      onWillAcceptWithDetails: (details) =>
          details.data.workspaceId == workspaceId,
      onMove: (details) =>
          _reportGap(context, details.data, details.offset, onHoverGap),
      onLeave: (_) => onLeave(),
      onAcceptWithDetails: (details) =>
          _reportGap(context, details.data, details.offset, onDropGap),
      builder: (context, _, _) {
        return Stack(
          clipBehavior: .none,
          children: <Widget>[
            child,
            if (showLeadingIndicator)
              const Positioned(
                left: -(AleraTokens.space8 + AleraTokens.space2) / 2,
                top: 0,
                bottom: 0,
                width: AleraTokens.space2,
                child: _SimpleStripInsertionIndicator(),
              ),
            if (showTrailingIndicator)
              const Positioned(
                right: (AleraTokens.space8 - AleraTokens.space2) / 2,
                top: 0,
                bottom: 0,
                width: AleraTokens.space2,
                child: _SimpleStripInsertionIndicator(),
              ),
          ],
        );
      },
    );
  }

  void _reportGap(
    BuildContext context,
    SimplePaneTabDragData data,
    Offset globalOffset,
    void Function(SimplePaneTabDragData data, int gapIndex) callback,
  ) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return;
    }
    final local = renderObject.globalToLocal(globalOffset);
    callback(
      data,
      resolveWorkbenchTabStripGapIndex(
        chipIndex: chipIndex,
        localDx: local.dx,
        chipWidth: renderObject.size.width,
      ),
    );
  }
}

class const _SimpleStripAppendDropTarget({
  required final String workspaceId,
  required final int tabCount,
  required final bool enabled,
  required final void Function(SimplePaneTabDragData data, int gapIndex)
  onHoverGap,
  required final VoidCallback onLeave,
  required final void Function(SimplePaneTabDragData data, int gapIndex)
  onDropGap,
  required final Widget child,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }
    return DragTarget<SimplePaneTabDragData>(
      onWillAcceptWithDetails: (details) =>
          details.data.workspaceId == workspaceId,
      onMove: (details) => onHoverGap(details.data, tabCount),
      onLeave: (_) => onLeave(),
      onAcceptWithDetails: (details) => onDropGap(details.data, tabCount),
      builder: (context, _, _) => child,
    );
  }
}

class const _SimpleStripInsertionIndicator() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: AleraTokens.accent,
        borderRadius: BorderRadius.all(.circular(AleraTokens.radiusSm)),
      ),
    );
  }
}
