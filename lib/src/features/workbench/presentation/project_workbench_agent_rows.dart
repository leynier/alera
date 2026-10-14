part of 'project_workbench_sidebar.dart';

class const _AgentRunRow({
  super.key,
  required final WorkspaceAgentRun run,
  required final bool isActive,
  required final VoidCallback onTap,
  required final VoidCallback onClose,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AgentRunRow> createState() => _AgentRunRowState();
}

class _AgentRunRowState extends ConsumerState<_AgentRunRow> {
  bool _hovered = false;

  WorkspaceTabRecord get _tab => widget.run.tab;

  AgentStatusEntry get _status => widget.run.status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = widget.isActive;
    final actionsVisible = _hovered || isActive;
    final hasBadge = agentRunStatusBadge(_status) != null;
    ref.watch(agentTitleAvailableProvider);
    final showTabTitle = ref.watch(
      settingsControllerProvider.select(
        (settings) => settings.agents.showTabTitlesInSidebar,
      ),
    );
    final description = _agentRunLabel(
      run: widget.run,
      showTabTitle: showTabTitle,
    );
    final chat = widget.run.chat;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        // The menu acts on a terminal agent: asking it, its run, its title.
        onSecondaryTapDown: chat != null
            ? null
            : (details) =>
                  unawaited(_openContextMenu(context, details.globalPosition)),
        child: AleraActiveRail(
          active: isActive,
          child: AnimatedContainer(
            width: .infinity,
            duration: AleraTokens.durationFast,
            decoration: BoxDecoration(
              color: isActive
                  ? AleraActiveRail.selectedColor
                  : (_hovered ? AleraTokens.surface : Colors.transparent),
              borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
            ),
            child: InkWell(
              onTap: widget.onTap,
              mouseCursor: SystemMouseCursors.click,
              borderRadius: .circular(AleraTokens.radiusSm),
              child: Padding(
                // A delegated chat sits under the chat that delegated it.
                padding: EdgeInsets.only(
                  left:
                      AleraTokens.space6 +
                      (chat?.depth ?? 0) * AleraTokens.space12,
                  right: AleraTokens.space6,
                  top: AleraTokens.space4,
                  bottom: AleraTokens.space4,
                ),
                child: Row(
                  crossAxisAlignment: .center,
                  children: <Widget>[
                    AgentRunStateIndicator(
                      status: _status,
                      size: 12,
                      stateLabeled: hasBadge,
                    ),
                    const SizedBox(width: AleraTokens.space6),
                    WorkspaceAgentRunIcon(
                      run: widget.run,
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
                    if (hasBadge) ...<Widget>[
                      const SizedBox(width: AleraTokens.space4),
                      Flexible(child: AgentRunStatusBadge(status: _status)),
                    ],
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
                            tooltip: chat == null
                                ? 'Close Terminal'
                                : 'Close Chat',
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
      ),
    );
  }

  Future<void> _openContextMenu(
    BuildContext context,
    Offset globalPosition,
  ) async {
    final titleAvailable = ref.read(agentTitleAvailableProvider).value == true;
    final run = RunTabIdentity.fromPayload(_tab.payload);
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<String>>[
        const AleraDropdownEntry<String>(
          value: 'askAgent',
          label: 'Ask Agent',
          leading: Icon(AleraIcons.inbox, size: 16),
        ),
        if (run != null)
          const AleraDropdownEntry<String>(
            value: 'viewRun',
            label: 'View Run',
            leading: Icon(AleraIcons.workspaceChildren, size: 16),
          ),
        if (titleAvailable)
          AleraDropdownEntry<String>(
            value: 'generateTitle',
            label: agentTitleActionLabel(_tab.payload),
            enabled: !isAgentTitleGenerating(_tab.payload),
            leading: const Icon(AleraIcons.ai, size: 16),
          ),
      ],
    );
    if (!context.mounted) return;
    if (selected == 'askAgent') {
      ref
          .read(activityNavigationProvider.notifier)
          .compose(targetHandle: _tab.terminalSessionId);
      return;
    }
    if (selected == 'viewRun' && run != null) {
      ref.read(activityNavigationProvider.notifier)
        ..open(ActivitySection.runs)
        ..selectRun(run.runId);
      return;
    }
    if (selected != 'generateTitle') return;
    try {
      await ref.read(agentTitleServiceProvider).generate(_tab);
    } on Object catch (error) {
      AleraToast.publish(
        message: 'Could not generate title: $error',
        tone: .error,
      );
    }
  }
}

String _agentRunLabel({
  required WorkspaceAgentRun run,
  required bool showTabTitle,
}) {
  if (showTabTitle || run.chat != null) {
    final title = run.tab.title.trim();
    if (title.isNotEmpty) {
      return title;
    }
  }
  return _agentRunDescription(run);
}

String _agentRunDescription(WorkspaceAgentRun run) {
  if (run.chat case final chat?) {
    final title = chat.title.trim();
    final name = title.isNotEmpty
        ? title
        : agentChatProviderFallbackLabel(chat.provider);
    return '$name · ${workspaceChatRunStateLabel(chat)}';
  }
  final status = run.status;
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
