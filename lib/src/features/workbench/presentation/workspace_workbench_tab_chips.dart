part of 'workspace_workbench_view.dart';

class _DraggableWorkspaceTabChip extends StatelessWidget {
  const _DraggableWorkspaceTabChip({
    required this.workspace,
    required this.groupId,
    required this.tab,
    required this.active,
    required this.terminalRuntime,
    required this.status,
    required this.groupTabs,
    required this.onSelect,
    required this.onClose,
    required this.onCloseTabs,
    required this.onRename,
    required this.onSplit,
  });

  final Workspace workspace;
  final String groupId;
  final WorkspaceTabRecord tab;
  final bool active;
  final TerminalRuntime terminalRuntime;
  final AgentStatusEntry? status;
  final List<WorkspaceTabRecord> groupTabs;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final ValueChanged<List<String>> onCloseTabs;
  final ValueChanged<String> onRename;
  final ValueChanged<WorkbenchDropZone> onSplit;

  @override
  Widget build(BuildContext context) {
    final session = tab.kind == WorkspaceTabKind.terminal
        ? terminalRuntime.sessionFor(workspace: workspace, tab: tab)
        : null;
    void selectAndFocus() {
      onSelect();
      session?.requestFocus();
    }

    return Padding(
      padding: const EdgeInsets.only(right: AleraTokens.space8),
      child: Draggable<_WorkspaceTabDragData>(
        data: _WorkspaceTabDragData(
          workspaceId: workspace.id,
          sourceGroupId: groupId,
          tabId: tab.id,
        ),
        feedback: _DraggedTabFeedback(
          tab: tab,
          title: session?.displayTitle ?? tab.title,
        ),
        childWhenDragging: Opacity(
          opacity: 0.45,
          child: _WorkspaceTabChip(
            tab: tab,
            terminalSession: session,
            status: status,
            active: active,
            groupTabs: groupTabs,
            onTap: selectAndFocus,
            onClose: onClose,
            onCloseTabs: onCloseTabs,
            onRename: onRename,
            onSplit: onSplit,
          ),
        ),
        child: _WorkspaceTabChip(
          tab: tab,
          terminalSession: session,
          status: status,
          active: active,
          groupTabs: groupTabs,
          onTap: selectAndFocus,
          onClose: onClose,
          onCloseTabs: onCloseTabs,
          onRename: onRename,
          onSplit: onSplit,
        ),
      ),
    );
  }
}

class _WorkspaceTabChip extends StatelessWidget {
  const _WorkspaceTabChip({
    required this.tab,
    required this.terminalSession,
    required this.status,
    required this.active,
    required this.groupTabs,
    required this.onTap,
    required this.onClose,
    required this.onCloseTabs,
    required this.onRename,
    required this.onSplit,
  });

  final WorkspaceTabRecord tab;
  final TerminalSessionHandle? terminalSession;
  final AgentStatusEntry? status;
  final bool active;
  final List<WorkspaceTabRecord> groupTabs;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final ValueChanged<List<String>> onCloseTabs;
  final ValueChanged<String> onRename;
  final ValueChanged<WorkbenchDropZone> onSplit;

  @override
  Widget build(BuildContext context) {
    final session = terminalSession;
    if (session == null) {
      return _buildChip(context, tab.title);
    }
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) => _buildChip(context, session.displayTitle),
    );
  }

  Future<void> _openContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final tabIndex = groupTabs.indexWhere(
      (candidate) => candidate.id == tab.id,
    );
    final closeOthers = <String>[
      for (final candidate in groupTabs)
        if (candidate.id != tab.id) candidate.id,
    ];
    final closeRight = tabIndex < 0
        ? const <String>[]
        : <String>[
            for (final candidate in groupTabs.skip(tabIndex + 1)) candidate.id,
          ];
    final selected = await showMenu<_TabMenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<_TabMenuAction>>[
        const AleraDropdownEntry<_TabMenuAction>(
          value: _TabMenuAction.splitUp,
          label: 'Split up',
          leading: _SplitDirectionGlyph(zone: WorkbenchDropZone.up),
        ),
        const AleraDropdownEntry<_TabMenuAction>(
          value: _TabMenuAction.splitDown,
          label: 'Split down',
          leading: _SplitDirectionGlyph(zone: WorkbenchDropZone.down),
        ),
        const AleraDropdownEntry<_TabMenuAction>(
          value: _TabMenuAction.splitLeft,
          label: 'Split left',
          leading: _SplitDirectionGlyph(zone: WorkbenchDropZone.left),
        ),
        const AleraDropdownEntry<_TabMenuAction>(
          value: _TabMenuAction.splitRight,
          label: 'Split right',
          leading: _SplitDirectionGlyph(zone: WorkbenchDropZone.right),
        ),
        const PopupMenuDivider(height: AleraTokens.space8),
        const AleraDropdownEntry<_TabMenuAction>(
          value: _TabMenuAction.close,
          label: 'Close',
          leading: Icon(Icons.close, size: 16),
        ),
        AleraDropdownEntry<_TabMenuAction>(
          value: _TabMenuAction.closeOthers,
          label: 'Close others',
          leading: Icon(
            Icons.tab_unselected,
            size: 16,
            color: closeOthers.isEmpty
                ? AleraTokens.foregroundFaint
                : AleraTokens.foreground,
          ),
          enabled: closeOthers.isNotEmpty,
        ),
        AleraDropdownEntry<_TabMenuAction>(
          value: _TabMenuAction.closeRight,
          label: 'Close tabs to the right',
          leading: Icon(
            Icons.keyboard_tab,
            size: 16,
            color: closeRight.isEmpty
                ? AleraTokens.foregroundFaint
                : AleraTokens.foreground,
          ),
          enabled: closeRight.isNotEmpty,
        ),
        const PopupMenuDivider(height: AleraTokens.space8),
        const AleraDropdownEntry<_TabMenuAction>(
          value: _TabMenuAction.changeTitle,
          label: 'Change title',
          leading: Icon(Icons.edit_outlined, size: 16),
        ),
      ],
    );
    if (selected == null || !context.mounted) {
      return;
    }
    switch (selected) {
      case _TabMenuAction.splitUp:
        onSplit(WorkbenchDropZone.up);
      case _TabMenuAction.splitDown:
        onSplit(WorkbenchDropZone.down);
      case _TabMenuAction.splitLeft:
        onSplit(WorkbenchDropZone.left);
      case _TabMenuAction.splitRight:
        onSplit(WorkbenchDropZone.right);
      case _TabMenuAction.close:
        onClose();
      case _TabMenuAction.closeOthers:
        onCloseTabs(closeOthers);
      case _TabMenuAction.closeRight:
        onCloseTabs(closeRight);
      case _TabMenuAction.changeTitle:
        final title = await showRenameDialog(
          context,
          title: 'Change terminal title',
          labelText: 'Terminal title',
          initialValue: terminalSession?.displayTitle ?? tab.title,
          confirmLabel: 'Change title',
        );
        if (title != null) {
          onRename(title);
        }
    }
  }

  Widget _buildChip(BuildContext context, String title) {
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          unawaited(_openContextMenu(context, details.globalPosition)),
      child: Material(
        color: active ? AleraTokens.surfaceElevated : AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        child: InkWell(
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
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
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _WorkspaceTabLeadingIcon(
                  tab: tab,
                  color: active
                      ? AleraTokens.foreground
                      : AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.space4),
                SizedBox.square(
                  dimension: 6,
                  child: status == null
                      ? const SizedBox.shrink()
                      : AgentStatusDot(status: status, size: 6),
                ),
                const SizedBox(width: AleraTokens.space4),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: _tabTitleMaxWidth(tab.kind),
                  ),
                  child: Text(
                    title,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: active
                          ? AleraTokens.foreground
                          : AleraTokens.foregroundMuted,
                    ),
                  ),
                ),
                const SizedBox(width: AleraTokens.space4),
                InkWell(
                  onTap: onClose,
                  mouseCursor: SystemMouseCursors.click,
                  borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      Icons.close,
                      size: 12,
                      color: AleraTokens.foregroundMuted,
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

enum _TabMenuAction {
  splitUp,
  splitDown,
  splitLeft,
  splitRight,
  close,
  closeOthers,
  closeRight,
  changeTitle,
}

class _WorkspaceTabLeadingIcon extends StatelessWidget {
  const _WorkspaceTabLeadingIcon({required this.tab, required this.color});

  final WorkspaceTabRecord tab;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return switch (tab.kind) {
      WorkspaceTabKind.editor => AleraFileIcon(
        pathOrName: tab.filePath ?? tab.title,
        kind: AleraFileIconKind.file,
        size: 12,
        fallbackColor: color,
      ),
      WorkspaceTabKind.gitDiff => Icon(
        Icons.fork_right_outlined,
        size: 12,
        color: color,
      ),
      WorkspaceTabKind.terminal => Icon(Icons.terminal, size: 12, color: color),
      WorkspaceTabKind.browser => Icon(Icons.public, size: 12, color: color),
    };
  }
}

double _tabTitleMaxWidth(WorkspaceTabKind kind) {
  return switch (kind) {
    WorkspaceTabKind.editor || WorkspaceTabKind.gitDiff => 180,
    WorkspaceTabKind.terminal || WorkspaceTabKind.browser => 92,
  };
}

class _DraggedTabFeedback extends StatelessWidget {
  const _DraggedTabFeedback({required this.tab, required this.title});

  final WorkspaceTabRecord tab;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AleraTokens.surfaceElevated,
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      child: Container(
        constraints: const BoxConstraints(minWidth: 140, maxWidth: 220),
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space8,
          vertical: AleraTokens.space6,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
          border: Border.all(color: AleraTokens.border),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: AleraTokens.shadowSoft,
              blurRadius: AleraTokens.space12,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _WorkspaceTabLeadingIcon(tab: tab, color: AleraTokens.foreground),
            const SizedBox(width: AleraTokens.space8),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AleraTokens.monoStyle.copyWith(
                  fontSize: 11,
                  color: AleraTokens.foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
