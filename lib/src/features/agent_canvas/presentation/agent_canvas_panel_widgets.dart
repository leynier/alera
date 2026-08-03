part of 'agent_canvas_panel.dart';

class _PanelToolbar extends StatelessWidget {
  const _PanelToolbar({
    required this.showHistory,
    required this.hasHistory,
    required this.onShowHistoryChanged,
  });

  final bool showHistory;
  final bool hasHistory;
  final ValueChanged<bool> onShowHistoryChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space8,
        vertical: AleraTokens.space6,
      ),
      child: Row(
        children: <Widget>[
          const Icon(AleraIcons.agent, size: 16, color: AleraTokens.info),
          const SizedBox(width: AleraTokens.space6),
          Expanded(
            child: Text(
              'Agent Canvas',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<bool>(
              value: showHistory,
              isDense: true,
              onChanged: hasHistory
                  ? (value) {
                      if (value != null) {
                        onShowHistoryChanged(value);
                      }
                    }
                  : null,
              items: const <DropdownMenuItem<bool>>[
                DropdownMenuItem<bool>(value: false, child: Text('Active')),
                DropdownMenuItem<bool>(value: true, child: Text('History')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CanvasList extends StatelessWidget {
  const _CanvasList({
    required this.pinned,
    required this.waiting,
    required this.live,
    required this.history,
    required this.selectedCanvasId,
    required this.onSelect,
  });

  final List<AgentCanvas> pinned;
  final List<AgentCanvas> waiting;
  final List<AgentCanvas> live;
  final List<AgentCanvas> history;
  final String? selectedCanvasId;
  final ValueChanged<AgentCanvas> onSelect;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    _addGroup(context, children, 'Pinned', pinned);
    _addGroup(context, children, 'Waiting', waiting);
    _addGroup(context, children, 'Live', live);
    _addGroup(context, children, 'History', history);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
      children: children,
    );
  }

  void _addGroup(
    BuildContext context,
    List<Widget> children,
    String title,
    List<AgentCanvas> canvases,
  ) {
    if (canvases.isEmpty) {
      return;
    }
    children.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(
          AleraTokens.space8,
          AleraTokens.space6,
          AleraTokens.space4,
          AleraTokens.space4,
        ),
        child: Text(
          title,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: AleraTokens.foregroundMuted,
          ),
        ),
      ),
    );
    children.addAll(
      canvases.map(
        (canvas) => _CanvasListTile(
          canvas: canvas,
          selected: canvas.id == selectedCanvasId,
          onTap: () => onSelect(canvas),
        ),
      ),
    );
  }
}

class _CanvasListTile extends StatelessWidget {
  const _CanvasListTile({
    required this.canvas,
    required this.selected,
    required this.onTap,
  });

  final AgentCanvas canvas;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      selected: selected,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space6,
      ),
      leading: Icon(
        canvas.hasPendingDecision ? AleraIcons.warning : AleraIcons.agent,
        size: 16,
        color: canvas.hasPendingDecision
            ? AleraTokens.warning
            : AleraTokens.foregroundMuted,
      ),
      title: Text(canvas.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        canvas.agentType,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: AleraBadge(label: 'r${canvas.revision}'),
      onTap: onTap,
    );
  }
}

class _CanvasDetails extends StatelessWidget {
  const _CanvasDetails({
    required this.canvas,
    required this.busy,
    required this.renderer,
    required this.onPinChanged,
    required this.onComplete,
    required this.onClose,
    required this.onRemove,
    required this.onAction,
  });

  final AgentCanvas canvas;
  final bool busy;
  final AgentSurfaceRenderer renderer;
  final ValueChanged<bool> onPinChanged;
  final VoidCallback? onComplete;
  final VoidCallback? onClose;
  final VoidCallback? onRemove;
  final AgentCanvasActionCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AleraTokens.space8,
            AleraTokens.space6,
            AleraTokens.space4,
            AleraTokens.space4,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  canvas.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              AleraBadge(label: 'Revision ${canvas.revision}'),
              const SizedBox(width: AleraTokens.space4),
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else ...<Widget>[
                AleraIconButton(
                  tooltip: canvas.pinned ? 'Unpin Canvas' : 'Pin Canvas',
                  icon: canvas.pinned ? AleraIcons.pinOff : AleraIcons.pin,
                  onPressed: () => onPinChanged(!canvas.pinned),
                ),
                if (onComplete != null)
                  AleraIconButton(
                    tooltip: 'Complete Canvas',
                    icon: AleraIcons.doneAll,
                    onPressed: onComplete,
                  ),
                if (onClose != null)
                  AleraIconButton(
                    tooltip: 'Close Canvas',
                    icon: AleraIcons.close,
                    onPressed: onClose,
                  ),
                if (onRemove != null)
                  AleraIconButton(
                    tooltip: 'Remove Canvas',
                    icon: AleraIcons.delete,
                    onPressed: onRemove,
                  ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: renderer.build(context, canvas: canvas, onAction: onAction),
        ),
      ],
    );
  }
}

const Set<String> _controlledActions = <String>{
  'resolveDecision',
  'approveExecutionPlan',
  'rejectExecutionPlan',
  'editPullRequestComment',
  'rerunValidation',
};

const Set<String> _destructiveActions = <String>{
  'stage',
  'unstage',
  'discard',
  'commit',
  'pull',
  'push',
  'mergePullRequest',
  'terminateTerminal',
  'deleteArtifact',
};

WorkbenchContextPanelTab? _contextPanelFrom(Object? value) {
  return switch (value) {
    'agentCanvas' => WorkbenchContextPanelTab.agentCanvas,
    'explorer' => WorkbenchContextPanelTab.explorer,
    'search' => WorkbenchContextPanelTab.search,
    'gitDiff' => WorkbenchContextPanelTab.gitDiff,
    'pullRequests' => WorkbenchContextPanelTab.pullRequests,
    _ => null,
  };
}
