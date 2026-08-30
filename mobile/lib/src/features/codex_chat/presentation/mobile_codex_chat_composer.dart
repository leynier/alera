part of 'mobile_codex_chat_screen.dart';

class const _MobileComposer({
  required final TextEditingController controller,
  required final FocusNode focusNode,
  required final MobileCodexController chatController,
  required final String workspaceId,
  required final String hostId,
  required final String tabId,
  required final MobileCodexState state,
  required final List<Map<String, Object?>> attachments,
  required final bool busy,
  required final bool interrupting,
  required final String? blockedMessage,
  required final Future<void> Function() onAttach,
  required final ValueChanged<Map<String, Object?>> onAddAttachment,
  required final ValueChanged<Map<String, Object?>> onCatalogSelection,
  required final ValueChanged<Map<String, Object?>> onRemoveAttachment,
  required final Future<void> Function() onSend,
  required final Future<void> Function() onSteer,
  required final Future<void> Function() onStop,
  required final bool canAttach,
  required final ValueChanged<String?> onModel,
  required final ValueChanged<String> onReasoning,
  required final ValueChanged<String> onSpeed,
  required final ValueChanged<String> onPermission,
  required final ValueChanged<bool> onPlan,
  required final ValueChanged<String?> onCollaboration,
  required final Future<void> Function() onCompact,
  required final Future<void> Function() onReview,
  required final VoidCallback onRename,
  required final Future<void> Function() onResume,
  required final Future<void> Function() onNew,
  required final Future<void> Function() onClear,
  required final bool supportsSessions,
  required final bool supportsTurnPolicy,
}) extends StatefulWidget {
  @override
  State<_MobileComposer> createState() => _MobileComposerState();
}

class _MobileComposerState extends State<_MobileComposer> {
  final GlobalKey<_MobileComposerCatalogState> _catalog =
      GlobalKey<_MobileComposerCatalogState>();
  var _historyIndex = -1;
  var _settingHistoryText = false;
  late int _threadGeneration;

  @override
  void initState() {
    super.initState();
    _threadGeneration = widget.chatController.threadGeneration;
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant _MobileComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    final threadGeneration = widget.chatController.threadGeneration;
    if (_threadGeneration != threadGeneration ||
        !listEquals(
          oldWidget.state.promptHistory,
          widget.state.promptHistory,
        )) {
      _historyIndex = -1;
    }
    _threadGeneration = threadGeneration;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!_settingHistoryText) _historyIndex = -1;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final inputDisabled =
        widget.interrupting ||
        widget.state.mcpInitializing ||
        widget.blockedMessage != null;
    final hasText = widget.controller.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AleraTokens.space12,
          AleraTokens.space4,
          AleraTokens.space12,
          AleraTokens.space8,
        ),
        child: Column(
          mainAxisSize: .min,
          children: <Widget>[
            _MobileComposerCatalog(
              key: _catalog,
              textController: widget.controller,
              chatController: widget.chatController,
              state: widget.state,
              workspaceId: widget.workspaceId,
              onAddAttachment: widget.onAddAttachment,
              onCatalogSelection: widget.onCatalogSelection,
            ),
            MobileAiDictationReviewBar(
              hostId: widget.hostId,
              targetKey: 'codex-${widget.tabId}',
            ),
            Container(
              decoration: BoxDecoration(
                color: AleraTokens.surfaceElevated,
                borderRadius: BorderRadius.circular(
                  AleraTokens.codexComposerRadius,
                ),
                border: Border.all(color: AleraTokens.border),
              ),
              clipBehavior: .antiAlias,
              child: Column(
                children: <Widget>[
                  if (widget.attachments.isNotEmpty)
                    _MobileComposerAttachments(
                      attachments: widget.attachments,
                      onRemove: widget.onRemoveAttachment,
                    ),
                  CallbackShortcuts(
                    bindings: <ShortcutActivator, VoidCallback>{
                      const SingleActivator(.enter): _submitOrAccept,
                      const SingleActivator(.enter, shift: true):
                          _insertLineBreak,
                    },
                    child: Focus(
                      canRequestFocus: false,
                      onKeyEvent: _handleArrowKey,
                      child: TextField(
                        controller: widget.controller,
                        focusNode: widget.focusNode,
                        enabled: !inputDisabled,
                        minLines: 2,
                        maxLines: AleraTokens.composeBarMaxLines,
                        textInputAction: .newline,
                        decoration: InputDecoration(
                          border: .none,
                          contentPadding: const EdgeInsets.fromLTRB(
                            AleraTokens.space16,
                            AleraTokens.space12,
                            AleraTokens.space16,
                            AleraTokens.space4,
                          ),
                          hintText: widget.state.mcpInitializing
                              ? 'Starting MCP Servers...'
                              : widget.blockedMessage ?? 'Ask Codex anything, @ for files, \$ for skills and apps, / for commands',
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AleraTokens.space8,
                      0,
                      AleraTokens.space8,
                      AleraTokens.space6,
                    ),
                    child: _MobileComposerControls(
                      composer: widget,
                      disabled: inputDisabled,
                      sendDisabled:
                          widget.interrupting ||
                          widget.blockedMessage != null ||
                          widget.state.mcpInitializing && !widget.busy,
                      hasText: hasText || widget.attachments.isNotEmpty,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submitOrAccept() {
    if (widget.blockedMessage != null ||
        widget.state.mcpInitializing ||
        widget.interrupting) {
      return;
    }
    if (_catalog.currentState?.acceptSelection() == true) return;
    unawaited(widget.busy ? widget.onSteer() : widget.onSend());
  }

  void _insertLineBreak() {
    if (widget.interrupting) return;
    final value = widget.controller.value;
    final start = value.selection.start < 0
        ? value.text.length
        : value.selection.start;
    final end = value.selection.end < 0
        ? value.text.length
        : value.selection.end;
    widget.controller.value = value.copyWith(
      text: value.text.replaceRange(start, end, '\n'),
      selection: .collapsed(offset: start + 1),
      composing: .empty,
    );
  }

  KeyEventResult _handleArrowKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_catalog.currentState?.moveSelection(1) == true || _nextPrompt()) {
        return KeyEventResult.handled;
      }
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_catalog.currentState?.moveSelection(-1) == true ||
          _previousPrompt()) {
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  bool _previousPrompt() {
    final history = widget.state.promptHistory;
    if (history.isEmpty ||
        _historyIndex < 0 && widget.controller.text.isNotEmpty) {
      return false;
    }
    _historyIndex = (_historyIndex + 1).clamp(0, history.length - 1);
    final text = history[history.length - 1 - _historyIndex];
    _setHistoryText(text);
    return true;
  }

  bool _nextPrompt() {
    if (_historyIndex < 0) return false;
    final history = widget.state.promptHistory;
    if (history.isEmpty || _historyIndex >= history.length) {
      _historyIndex = -1;
      return false;
    }
    _historyIndex -= 1;
    final text = _historyIndex < 0
        ? ''
        : history[history.length - 1 - _historyIndex];
    _setHistoryText(text);
    return true;
  }

  void _setHistoryText(String text) {
    _settingHistoryText = true;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: .collapsed(offset: text.length),
    );
    _settingHistoryText = false;
  }
}

class const _MobilePermissionButton({
  required final String value,
  required final bool enabled,
  required final bool supportsAutoReview,
  required final ValueChanged<String> onSelected,
  final bool compact = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final full = value == 'never';
    return TextButton.icon(
      onPressed: enabled ? () => _show(context) : null,
      icon: Icon(
        full ? Icons.warning_amber_rounded : Icons.shield_outlined,
        size: AleraTokens.space12,
      ),
      label: Text(
        compact
            ? switch (value) {
                'never' => 'Full',
                'auto-review' => 'Approve',
                _ => 'Ask',
              }
            : switch (value) {
                'never' => 'Full Access',
                'auto-review' => 'Approve For Me',
                _ => 'Ask Approval',
              },
      ),
      style: TextButton.styleFrom(
        foregroundColor: full
            ? AleraTokens.warning
            : AleraTokens.foregroundMuted,
      ),
    );
  }

  Future<void> _show(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: .min,
        children: <Widget>[
          const ListTile(title: Text('How Should Codex Actions Be Approved?')),
          _permissionTile(
            sheetContext,
            value: 'untrusted',
            title: 'Ask For Approval',
            subtitle: 'Always ask to edit external files and use the internet.',
            icon: Icons.front_hand_outlined,
          ),
          if (supportsAutoReview)
            _permissionTile(
              sheetContext,
              value: 'auto-review',
              title: 'Approve For Me',
              subtitle: 'Only ask for actions detected as potentially unsafe.',
              icon: Icons.shield_outlined,
            ),
          _permissionTile(
            sheetContext,
            value: 'never',
            title: 'Full Access',
            subtitle: 'Unrestricted access to the internet and local files.',
            icon: Icons.warning_amber_rounded,
          ),
        ],
      ),
    ),
  );

  Widget _permissionTile(
    BuildContext context, {
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
  }) => ListTile(
    minTileHeight: AleraTokens.minTapTarget,
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: this.value == value ? const Icon(Icons.check) : null,
    onTap: () async {
      if (value == 'never' && !await _confirmFullAccess(context)) return;
      onSelected(value);
      if (context.mounted) Navigator.of(context).pop();
    },
  );
}

Future<bool> _confirmFullAccess(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Turn On Full Access?'),
        icon: const Icon(Icons.warning_amber_rounded, color: AleraTokens.error),
        content: const Text(
          'Codex will be able to run commands, use the internet, and create, edit, or delete files without your permission.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AleraTokens.error),
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.warning_amber_rounded),
            label: const Text('Confirm'),
          ),
        ],
      ),
    ) ??
    false;

class const _MobileContextButton({required final MobileCodexState state})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final used = state.contextUsed;
    final limit = state.contextLimit;
    final ratio = used != null && limit != null && limit > 0
        ? (used / limit).clamp(0.0, 1.0)
        : 0.0;
    return IconButton(
      tooltip: 'Context Window',
      visualDensity: .compact,
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: ListTile(
            title: const Text('Context Window'),
            subtitle: Text(
              used == null || limit == null
                  ? 'Usage is unavailable.'
                  : '${(ratio * 100).round()}% used - $used / $limit tokens',
            ),
          ),
        ),
      ),
      icon: SizedBox.square(
        dimension: AleraTokens.space16,
        child: CircularProgressIndicator(
          value: ratio,
          strokeWidth: AleraTokens.space2,
          color: AleraTokens.foregroundMuted,
        ),
      ),
    );
  }
}
