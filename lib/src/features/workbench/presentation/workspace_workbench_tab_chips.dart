part of 'workspace_workbench_view.dart';

class const _DraggableWorkspaceTabChip({
  required final Workspace workspace,
  required final String groupId,
  required final WorkspaceTabRecord tab,
  required final bool active,
  required final TerminalRuntime terminalRuntime,
  required final AgentStatusEntry? status,
  required final bool completionAcknowledged,
  required final List<WorkspaceTabRecord> groupTabs,
  required final VoidCallback onSelect,
  required final VoidCallback onClose,
  required final ValueChanged<List<String>> onCloseTabs,
  required final ValueChanged<String> onRename,
  required final ValueChanged<WorkbenchDropZone> onSplit,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tabDragController = _WorkbenchTabDragScope.controllerOf(context);
    // peek, not sessionFor: building a handle here allocated a full xterm
    // buffer for every tab of the active workspace, including ones the user
    // never opened. Selecting the tab is what actually needs a session.
    final session = tab.kind == WorkspaceTabKind.terminal
        ? terminalRuntime.peekSession(tab.id)
        : null;
    void selectAndFocus() {
      onSelect();
      if (tab.kind != WorkspaceTabKind.terminal) {
        return;
      }
      terminalRuntime.sessionFor(workspace: workspace, tab: tab).requestFocus();
    }

    return Padding(
      padding: const EdgeInsets.only(right: AleraTokens.space8),
      child: Draggable<_WorkspaceTabDragData>(
        onDragStarted: tabDragController.begin,
        onDragEnd: (_) => tabDragController.finishAfterLayout(),
        onDraggableCanceled: (_, _) => tabDragController.finishAfterLayout(),
        data: _WorkspaceTabDragData(
          workspaceId: workspace.id,
          sourceGroupId: groupId,
          tabId: tab.id,
        ),
        feedback: _DraggedTabFeedback(
          tab: tab,
          title: session?.displayTitle ?? _workspaceTabTitle(tab),
        ),
        childWhenDragging: Opacity(
          opacity: 0.45,
          child: _WorkspaceTabChip(
            tab: tab,
            terminalSession: session,
            status: status,
            completionAcknowledged: completionAcknowledged,
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
          completionAcknowledged: completionAcknowledged,
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

class const _WorkspaceTabChip({
  required final WorkspaceTabRecord tab,
  required final TerminalSessionHandle? terminalSession,
  required final AgentStatusEntry? status,
  required final bool completionAcknowledged,
  required final bool active,
  required final List<WorkspaceTabRecord> groupTabs,
  required final VoidCallback onTap,
  required final VoidCallback onClose,
  required final ValueChanged<List<String>> onCloseTabs,
  required final ValueChanged<String> onRename,
  required final ValueChanged<WorkbenchDropZone> onSplit,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(agentTitleAvailableProvider);
    final session = terminalSession;
    if (session == null) {
      return _buildChip(context, _workspaceTabTitle(tab), ref);
    }
    // Title only: listening to the whole session rebuilt every chip on each
    // OSC title change, which shells emit per prompt.
    return ValueListenableBuilder<String>(
      valueListenable: session.titleListenable,
      builder: (context, title, _) => _buildChip(context, title, ref),
    );
  }

  Widget _buildChip(BuildContext context, String title, WidgetRef ref) {
    return GestureDetector(
      onSecondaryTapDown: (details) =>
          unawaited(_openContextMenu(context, details.globalPosition, ref)),
      child: Material(
        color: active ? AleraTokens.surfaceElevated : AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        child: InkWell(
          onTap: onTap,
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
                _WorkspaceTabLeadingIcon(
                  tab: tab,
                  color: active
                      ? AleraTokens.foreground
                      : AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.space4),
                SizedBox.square(
                  dimension: 6,
                  child: () {
                    final entry = status;
                    if (entry == null) {
                      return const SizedBox.shrink();
                    }
                    return Tooltip(
                      message: workbenchTabAttentionTooltip(
                        status: entry,
                        completionAcknowledged: completionAcknowledged,
                      ),
                      child: AleraStatusDot(
                        active: true,
                        size: 6,
                        color: workbenchTabAttentionDotColor(
                          status: entry,
                          completionAcknowledged: completionAcknowledged,
                        ),
                      ),
                    );
                  }(),
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
                    overflow: .ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: active
                          ? AleraTokens.foreground
                          : AleraTokens.foregroundMuted,
                      fontStyle: tab.isPreview
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ),
                const SizedBox(width: AleraTokens.space4),
                if (tab.payload['agentTitleStatus'] == 'generating') ...[
                  const Tooltip(
                    message: 'Generating title...',
                    child: Icon(
                      AleraIcons.loading,
                      size: AleraTokens.iconSm,
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space4),
                ],
                InkWell(
                  onTap: onClose,
                  mouseCursor: SystemMouseCursors.click,
                  borderRadius: .circular(AleraTokens.radiusSm),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(
                      AleraIcons.close,
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
  keepOpen,
  close,
  closeOthers,
  closeRight,
  changeTitle,
  generateTitle,
}

class const _WorkspaceTabLeadingIcon({
  required final WorkspaceTabRecord tab,
  required final Color color,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return switch (tab.kind) {
      WorkspaceTabKind.editor ||
      WorkspaceTabKind.markdownViewer ||
      WorkspaceTabKind.pdf => AleraFileIcon(
        pathOrName: tab.filePath ?? tab.title,
        kind: .file,
        size: 12,
        fallbackColor: color,
      ),
      WorkspaceTabKind.gitDiff => Icon(
        AleraIcons.gitBranch,
        size: 12,
        color: color,
      ),
      WorkspaceTabKind.terminal => Icon(
        AleraIcons.terminal,
        size: 12,
        color: color,
      ),
    };
  }
}

double _tabTitleMaxWidth(WorkspaceTabKind kind) {
  return switch (kind) {
    WorkspaceTabKind.editor ||
    WorkspaceTabKind.markdownViewer ||
    WorkspaceTabKind.pdf ||
    WorkspaceTabKind.gitDiff => 180,
    WorkspaceTabKind.terminal => 92,
  };
}

class const _DraggedTabFeedback({
  required final WorkspaceTabRecord tab,
  required final String title,
}) extends StatelessWidget {
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
          mainAxisSize: .min,
          children: <Widget>[
            _WorkspaceTabLeadingIcon(tab: tab, color: AleraTokens.foreground),
            const SizedBox(width: AleraTokens.space8),
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: .ellipsis,
                style: AleraTokens.monoStyle.copyWith(
                  fontSize: 11,
                  color: AleraTokens.foreground,
                  fontStyle: tab.isPreview
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
