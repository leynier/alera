part of 'project_workbench_sidebar.dart';

class _AgentRunRow extends StatefulWidget {
  const _AgentRunRow({
    required this.workspace,
    required this.tab,
    required this.status,
    required this.isActive,
    required this.onTap,
    required this.onClose,
  });

  final Workspace workspace;
  final WorkspaceTabRecord tab;
  final AgentStatusEntry status;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;

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
    final primaryLabel = _agentRunPrimaryLabel(widget.status);
    final secondaryLabel = _agentRunSecondaryLabel(widget.status);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AleraTokens.space2),
        child: AnimatedContainer(
          duration: AleraTokens.durationFast,
          decoration: BoxDecoration(
            color: isActive
                ? AleraTokens.surfaceElevated
                : (_hovered ? AleraTokens.surface : Colors.transparent),
            borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
          ),
          child: InkWell(
            onTap: widget.onTap,
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space8,
                vertical: AleraTokens.space6,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: AgentRunStateIndicator(
                      status: widget.status,
                      size: 12,
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space6),
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: AgentIdentityIcon(
                      agentType: widget.status.agentType,
                      size: 13,
                      color: isActive
                          ? AleraTokens.foreground
                          : AleraTokens.foregroundMuted,
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          primaryLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: isActive
                                ? AleraTokens.foreground
                                : AleraTokens.foregroundMuted,
                            fontWeight: isActive
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                        if (secondaryLabel.isNotEmpty) ...<Widget>[
                          const SizedBox(height: AleraTokens.space2),
                          Text(
                            secondaryLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: AleraTokens.foregroundFaint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IgnorePointer(
                    ignoring: !actionsVisible,
                    child: AnimatedOpacity(
                      opacity: actionsVisible ? 1 : 0,
                      duration: AleraTokens.durationFast,
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: AleraTokens.space4,
                        ),
                        child: AleraIconButton(
                          tooltip: 'Close terminal',
                          onPressed: widget.onClose,
                          icon: AleraIcons.close,
                          iconSize: 12,
                          minSize: 22,
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
      ),
    );
  }
}

String _agentRunPrimaryLabel(AgentStatusEntry status) {
  final prompt = status.prompt.trim();
  if (prompt.isNotEmpty) {
    return prompt;
  }
  return agentRunStateLabel(status);
}

String _agentRunSecondaryLabel(AgentStatusEntry status) {
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
