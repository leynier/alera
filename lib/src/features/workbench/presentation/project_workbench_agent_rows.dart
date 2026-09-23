part of 'project_workbench_sidebar.dart';

class const _AgentRunRow({
  super.key,
  required final WorkspaceTabRecord tab,
  required final AgentStatusEntry status,
  required final bool isActive,
  required final VoidCallback onTap,
  required final VoidCallback onClose,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AgentRunRow> createState() => _AgentRunRowState();
}

class _AgentRunRowState extends ConsumerState<_AgentRunRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = widget.isActive;
    final actionsVisible = _hovered || isActive;
    ref.watch(agentTitleAvailableProvider);
    final showTabTitle = ref.watch(
      settingsControllerProvider.select(
        (settings) => settings.agents.showTabTitlesInSidebar,
      ),
    );
    final description = _agentRunLabel(
      tab: widget.tab,
      status: widget.status,
      showTabTitle: showTabTitle,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onSecondaryTapDown: (details) =>
            unawaited(_openContextMenu(context, details.globalPosition)),
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
                        fontWeight: isActive
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
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
                          tooltip: 'Close Terminal',
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
      ),
    );
  }

  Future<void> _openContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    if (ref.read(agentTitleAvailableProvider).value != true) {
      return;
    }
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<String>>[
        AleraDropdownEntry<String>(
          value: 'generateTitle',
          label: agentTitleActionLabel(widget.tab.payload),
          enabled: !isAgentTitleGenerating(widget.tab.payload),
          leading: const Icon(AleraIcons.ai, size: 16),
        ),
      ],
    );
    if (selected != 'generateTitle' || !context.mounted) {
      return;
    }
    try {
      await ref.read(agentTitleServiceProvider).generate(widget.tab);
    } on Object catch (error) {
      AleraToast.publish(
        message: 'Could not generate title: $error',
        tone: .error,
      );
    }
  }
}

String _agentRunLabel({
  required WorkspaceTabRecord tab,
  required AgentStatusEntry status,
  required bool showTabTitle,
}) {
  if (showTabTitle) {
    final title = tab.title.trim();
    if (title.isNotEmpty) {
      return title;
    }
  }
  return _agentRunDescription(status);
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
