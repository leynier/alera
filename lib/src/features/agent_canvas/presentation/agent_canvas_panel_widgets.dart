part of 'agent_canvas_panel.dart';

class const _PanelToolbar({
  required final bool showHistory,
  required final bool hasHistory,
  required final ValueChanged<bool> onShowHistoryChanged,
}) extends StatelessWidget {
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

class const _CanvasList({
  required final List<AgentCanvas> pinned,
  required final List<AgentCanvas> waiting,
  required final List<AgentCanvas> live,
  required final List<AgentCanvas> history,
  required final String? selectedCanvasId,
  required final ValueChanged<AgentCanvas> onSelect,
}) extends StatelessWidget {
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
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(fontWeight: .w600, color: AleraTokens.foregroundMuted),
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

class const _CanvasListTile({
  required final AgentCanvas canvas,
  required final bool selected,
  required final VoidCallback onTap,
}) extends StatelessWidget {
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
      title: Text(canvas.title, maxLines: 1, overflow: .ellipsis),
      subtitle: Text(canvas.agentType, maxLines: 1, overflow: .ellipsis),
      trailing: AleraBadge(label: 'r${canvas.revision}'),
      onTap: onTap,
    );
  }
}

class const _CanvasDetails({
  required final AgentCanvas canvas,
  required final bool busy,
  required final AgentSurfaceRenderer renderer,
  required final ValueChanged<bool> onPinChanged,
  required final VoidCallback? onComplete,
  required final VoidCallback? onClose,
  required final VoidCallback? onRemove,
  required final AgentCanvasActionCallback onAction,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
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
                  overflow: .ellipsis,
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
