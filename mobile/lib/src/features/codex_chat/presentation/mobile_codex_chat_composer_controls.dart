part of 'mobile_codex_chat_screen.dart';

class const _MobileComposerControls({
  required final _MobileComposer composer,
  required final bool disabled,
  required final bool sendDisabled,
  required final bool hasText,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= AleraTokens.codexComposerSingleRowMinWidth) {
        return Row(
          children: <Widget>[
            ..._leftControls(context),
            const Spacer(),
            ..._rightControls(),
          ],
        );
      }
      return Column(
        mainAxisSize: .min,
        children: <Widget>[
          Row(children: _leftControls(context, compact: true)),
          const SizedBox(height: AleraTokens.space2),
          Row(children: <Widget>[const Spacer(), ..._rightControls()]),
        ],
      );
    },
  );

  List<Widget> _leftControls(BuildContext context, {bool compact = false}) =>
      <Widget>[
        MobileAiDictationControl(
          hostId: composer.hostId,
          targetKey: 'codex-${composer.tabId}',
          workspaceId: composer.workspaceId,
          tabId: composer.tabId,
          controller: composer.controller,
          enabled: !disabled,
        ),
        IconButton(
          tooltip: 'Add Attachment',
          visualDensity: VisualDensity.compact,
          onPressed: composer.canAttach && !disabled
              ? () => unawaited(composer.onAttach())
              : null,
          icon: const Icon(Icons.add),
        ),
        _MobilePermissionButton(
          value:
              !composer.supportsTurnPolicy &&
                  composer.state.permissionMode == 'auto-review'
              ? 'untrusted'
              : composer.state.permissionMode,
          enabled: !disabled,
          supportsAutoReview: composer.supportsTurnPolicy,
          compact: compact,
          onSelected: composer.onPermission,
        ),
        const SizedBox(width: AleraTokens.space4),
        TextButton.icon(
          onPressed: disabled
              ? null
              : () => composer.onPlan(!composer.state.planMode),
          icon: Icon(
            composer.state.planMode ? Icons.lightbulb : Icons.lightbulb_outline,
            size: AleraTokens.space12,
          ),
          label: const Text('Plan'),
          style: TextButton.styleFrom(
            foregroundColor: composer.state.planMode
                ? AleraTokens.foreground
                : AleraTokens.foregroundMuted,
          ),
        ),
        if (composer.supportsSessions)
          PopupMenuButton<String>(
            tooltip: 'Codex Chat Actions',
            enabled: !disabled,
            onSelected: (value) {
              switch (value) {
                case 'fork':
                  unawaited(
                    context
                        .findAncestorStateOfType<_MobileCodexChatScreenState>()
                        ?._forkHistory(),
                  );
                case 'resume':
                  unawaited(composer.onResume());
                case 'new':
                  unawaited(composer.onNew());
                case 'clear':
                  unawaited(composer.onClear());
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              PopupMenuItem(
                value: 'fork',
                enabled:
                    composer.state.supportsFork &&
                    !composer.state.historyLocked &&
                    (composer.state.hasCompletedTurns ??
                        (composer.state.historyNextCursor != null ||
                            composer.state.timelineCells.any(
                              (cell) =>
                                  cell.turnId != null &&
                                  cell.turnId != composer.state.activeTurnId,
                            ))),
                child: const Text('Fork Chat'),
              ),
              PopupMenuItem(
                value: 'resume',
                enabled: !composer.busy,
                child: const Text('Resume Thread'),
              ),
              PopupMenuItem(
                value: 'new',
                enabled: !composer.busy,
                child: const Text('Start New Chat'),
              ),
              PopupMenuItem(
                value: 'clear',
                enabled: !composer.busy,
                child: const Text('Clear Chat'),
              ),
            ],
            icon: const Icon(Icons.more_horiz),
          ),
      ];

  List<Widget> _rightControls() => <Widget>[
    _MobileContextButton(state: composer.state),
    Flexible(
      child: _MobileModelMenuButton(
        state: composer.state,
        onModel: composer.onModel,
        onReasoning: composer.onReasoning,
        onSpeed: composer.onSpeed,
        onCollaboration: composer.onCollaboration,
      ),
    ),
    const SizedBox(width: AleraTokens.space4),
    _MobileSendButton(
      busy: composer.busy,
      disabled: sendDisabled,
      hasText: hasText,
      canSteer: hasText && !disabled,
      onSend: composer.onSend,
      onSteer: composer.onSteer,
      onStop: composer.onStop,
    ),
  ];
}
