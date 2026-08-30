part of 'project_workbench_sidebar.dart';

class const _AgentRunRow({
  super.key,
  required final WorkspaceTabRecord tab,
  required final AgentStatusEntry status,
  required final bool isActive,
  required final VoidCallback onTap,
  required final VoidCallback onClose,
}) extends StatefulWidget {
  @override
  State<_AgentRunRow> createState() => _AgentRunRowState();
}

class _AgentRunRowState extends State<_AgentRunRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = widget.isActive;
    final actionsVisible = _hovered || isActive;
    final description = _agentRunDescription(widget.status);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        width: .infinity,
        duration: AleraTokens.durationFast,
        decoration: BoxDecoration(
          color: isActive
              ? AleraTokens.accentSubtle
              : (_hovered ? AleraTokens.surface : Colors.transparent),
          borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        ),
        child: InkWell(
          onTap: widget.onTap,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: .circular(AleraTokens.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space6,
              vertical: AleraTokens.space4,
            ),
            child: Row(
              crossAxisAlignment: .center,
              children: <Widget>[
                AgentRunStateIndicator(status: widget.status, size: 12),
                const SizedBox(width: AleraTokens.space6),
                AgentIdentityIcon(
                  agentType: widget.status.agentType,
                  size: 13,
                  color: isActive
                      ? AleraTokens.foreground
                      : AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.space6),
                Expanded(
                  child: Text(
                    description,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isActive
                          ? AleraTokens.foreground
                          : AleraTokens.foregroundMuted,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                IgnorePointer(
                  ignoring: !actionsVisible,
                  child: AnimatedOpacity(
                    opacity: actionsVisible ? 1 : 0,
                    duration: AleraTokens.durationFast,
                    child: Padding(
                      padding: const EdgeInsets.only(left: AleraTokens.space4),
                      child: AleraIconButton(
                        tooltip: widget.tab.kind == WorkspaceTabKind.codex
                            ? 'Close Codex'
                            : 'Close Terminal',
                        onPressed: widget.onClose,
                        icon: AleraIcons.close,
                        iconSize: 12,
                        minSize: 20,
                        borderRadius: AleraTokens.radiusSm,
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

String _agentRunDescription(AgentStatusEntry status) {
  if (status.state == AgentStatusState.working) {
    final toolName = status.toolName?.trim() ?? '';
    final toolInput = status.toolInput?.trim() ?? '';
    if (toolName.isNotEmpty && toolInput.isNotEmpty) {
      return '$toolName: $toolInput';
    }
    if (toolName.isNotEmpty) {
      return toolName;
    }
  }
  final assistantMessage = status.lastAssistantMessage?.trim() ?? '';
  if (assistantMessage.isNotEmpty) {
    return assistantMessage;
  }
  return '${agentDisplayName(status.agentType)} · ${agentRunStateLabel(status)}';
}
