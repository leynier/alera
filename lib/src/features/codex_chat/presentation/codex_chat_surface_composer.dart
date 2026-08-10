part of 'codex_chat_surface.dart';

class _CodexComposer extends StatefulWidget {
  const _CodexComposer({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.interrupting,
    required this.attachments,
    required this.draftItems,
    required this.savedPrompts,
    required this.state,
    required this.workspacePath,
    required this.workspaceFiles,
    required this.onModelChanged,
    required this.onReasoningChanged,
    required this.onSpeedChanged,
    required this.onPermissionChanged,
    required this.onPlanChanged,
    required this.onCollaborationChanged,
    required this.onDraftItemSelected,
    required this.onCommand,
    required this.onSend,
    required this.onStop,
    required this.onAddAttachment,
    required this.onPaste,
    required this.onRemoveAttachment,
    required this.onRemoveDraftItem,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final bool interrupting;
  final List<CodexInputAttachment> attachments;
  final List<CodexDraftItem> draftItems;
  final List<native.CodexSavedPrompt> savedPrompts;
  final CodexChatState state;
  final String workspacePath;
  final WorkspaceFileService workspaceFiles;
  final ValueChanged<String?> onModelChanged;
  final ValueChanged<String> onReasoningChanged;
  final ValueChanged<String> onSpeedChanged;
  final ValueChanged<String> onPermissionChanged;
  final ValueChanged<bool> onPlanChanged;
  final ValueChanged<String?> onCollaborationChanged;
  final ValueChanged<CodexDraftItem> onDraftItemSelected;
  final ValueChanged<CodexComposerCommand> onCommand;
  final VoidCallback onSend;
  final Future<void> Function() onStop;
  final Future<void> Function() onAddAttachment;
  final Future<void> Function() onPaste;
  final ValueChanged<CodexInputAttachment> onRemoveAttachment;
  final ValueChanged<CodexDraftItem> onRemoveDraftItem;

  @override
  State<_CodexComposer> createState() => _CodexComposerState();
}

class _CodexComposerState extends State<_CodexComposer> {
  final GlobalKey<PopupMenuButtonState<String>> _modelMenu = GlobalKey();
  final GlobalKey<PopupMenuButtonState<String>> _reasoningMenu = GlobalKey();
  Timer? _queryDebounce;
  native.WorkspaceQuickOpenSession? _quickOpenSession;
  Future<void>? _quickOpenRefresh;
  List<String> _mentionFiles = const <String>[];
  List<CodexComposerEntry> _commands = const <CodexComposerEntry>[];
  int _selectedIndex = 0;
  int _queryGeneration = 0;
  bool _hasText = false;
  bool _mentionActive = false;

  void _setComposerState(VoidCallback callback) => setState(callback);

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_onTextChanged);
    widget.focusNode.onKeyEvent = _handleKeyEvent;
  }

  @override
  void didUpdateWidget(covariant _CodexComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspacePath != widget.workspacePath) {
      _mentionActive = false;
      _mentionFiles = const <String>[];
      unawaited(_stopQuickOpen());
    }
  }

  @override
  void dispose() {
    _queryDebounce?.cancel();
    widget.controller.removeListener(_onTextChanged);
    if (widget.focusNode.onKeyEvent == _handleKeyEvent) {
      widget.focusNode.onKeyEvent = null;
    }
    final session = _quickOpenSession;
    if (session != null) {
      unawaited(widget.workspaceFiles.stopQuickOpenSession(session: session));
    }
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyV &&
        (Platform.isMacOS
            ? HardwareKeyboard.instance.isMetaPressed
            : HardwareKeyboard.instance.isControlPressed)) {
      unawaited(widget.onPaste());
      return KeyEventResult.handled;
    }
    if (event is! KeyDownEvent ||
        (_commands.isEmpty && _mentionFiles.isEmpty)) {
      return KeyEventResult.ignored;
    }
    final length = _commands.isNotEmpty
        ? _commands.length
        : _mentionFiles.length;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _selectedIndex = (_selectedIndex - 1).clamp(0, length - 1),
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(
        () => _selectedIndex = (_selectedIndex + 1).clamp(0, length - 1),
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _clearOverlay();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_commands.isNotEmpty) {
        _selectCommand(_commands[_selectedIndex]);
      } else {
        _selectMention(_mentionFiles[_selectedIndex]);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _replaceActive(RegExp pattern, String replacement) {
    final cursor = widget.controller.selection.baseOffset;
    if (cursor < 0) return;
    final before = widget.controller.text.substring(0, cursor);
    final match = pattern.firstMatch(before);
    if (match == null) return;
    final after = widget.controller.text.substring(cursor);
    final next = '${before.substring(0, match.start)}$replacement$after';
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: match.start + replacement.length,
      ),
    );
  }

  void _selectMention(String path) {
    final token = '@$path';
    _replaceActive(RegExp(r'@\S*$'), '$token ');
    widget.onDraftItemSelected(
      CodexDraftItem(
        id: 'mention-$path',
        kind: CodexDraftItemKind.mention,
        name: p.basename(path),
        path: path,
        tokenText: token,
      ),
    );
    _clearOverlay();
  }

  void _selectCommand(CodexComposerEntry entry) {
    _clearOverlay();
    final savedPrompt = entry.savedPrompt;
    if (savedPrompt != null) {
      _replaceActive(RegExp(r'^/\S*$'), '/${savedPrompt.name} ');
      return;
    }
    final command = entry.builtin!;
    if (command == CodexComposerCommand.rename) {
      _replaceActive(RegExp(r'^/\S*$'), '/rename ');
      return;
    }
    if (command == CodexComposerCommand.mention) {
      _replaceActive(RegExp(r'^/\S*$'), '@');
      return;
    }
    widget.controller.clear();
    widget.onCommand(command);
  }

  void _insertLineBreak() {
    final value = widget.controller.value;
    final start = value.selection.start < 0
        ? value.text.length
        : value.selection.start;
    final end = value.selection.end < 0
        ? value.text.length
        : value.selection.end;
    widget.controller.value = value.copyWith(
      text: value.text.replaceRange(start, end, '\n'),
      selection: TextSelection.collapsed(offset: start + 1),
      composing: TextRange.empty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final contextUsed = widget.state.snapshot.contextUsed;
    final contextLimit = widget.state.snapshot.contextLimit;
    final canSubmit =
        _hasText ||
        widget.attachments.isNotEmpty ||
        widget.draftItems.isNotEmpty;
    final showSend = canSubmit || !widget.busy;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AleraTokens.codexConversationMaxWidth,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_commands.isNotEmpty)
                _CodexCommandOverlay(
                  commands: _commands,
                  selectedIndex: _selectedIndex,
                  onSelected: _selectCommand,
                ),
              if (_mentionFiles.isNotEmpty)
                _CodexMentionOverlay(
                  paths: _mentionFiles,
                  selectedIndex: _selectedIndex,
                  onSelected: _selectMention,
                ),
              if (widget.busy)
                const Padding(
                  padding: EdgeInsets.only(bottom: AleraTokens.space8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.all(
                      Radius.circular(AleraTokens.radiusSm),
                    ),
                    child: LinearProgressIndicator(
                      minHeight: AleraTokens.space2,
                    ),
                  ),
                ),
              Stack(
                children: <Widget>[
                  AiDictationTarget(
                    controller: widget.controller,
                    focusNode: widget.focusNode,
                    initialPrompt:
                        'The user is chatting with Codex about a software task.',
                    builder: (context, targetId) => DecoratedBox(
                      decoration: BoxDecoration(
                        color: AleraTokens.surfaceVariant,
                        borderRadius: BorderRadius.circular(
                          AleraTokens.radiusXl,
                        ),
                        border: Border.all(color: AleraTokens.border),
                      ),
                      child: Column(
                        children: <Widget>[
                          _CodexDraftItemBar(
                            items: widget.draftItems,
                            onRemove: widget.onRemoveDraftItem,
                          ),
                          _CodexAttachmentBar(
                            attachments: widget.attachments,
                            onRemove: widget.onRemoveAttachment,
                          ),
                          CallbackShortcuts(
                            bindings: <ShortcutActivator, VoidCallback>{
                              const SingleActivator(
                                LogicalKeyboardKey.enter,
                              ): () {
                                if (canSubmit) widget.onSend();
                              },
                              const SingleActivator(
                                LogicalKeyboardKey.enter,
                                shift: true,
                              ): _insertLineBreak,
                            },
                            child: TextField(
                              controller: widget.controller,
                              focusNode: widget.focusNode,
                              enabled: !widget.interrupting,
                              minLines: 2,
                              maxLines: 6,
                              textInputAction: TextInputAction.newline,
                              decoration: const InputDecoration(
                                hintText:
                                    'Ask Codex anything, @ to add files, / for commands',
                                filled: true,
                                fillColor: Colors.transparent,
                                hoverColor: Colors.transparent,
                                contentPadding: EdgeInsets.fromLTRB(
                                  AleraTokens.space12,
                                  AleraTokens.space16,
                                  AleraTokens.space32,
                                  AleraTokens.space8,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AleraTokens.space8,
                              0,
                              AleraTokens.space8,
                              AleraTokens.space8,
                            ),
                            child: Row(
                              children: <Widget>[
                                AiDictationControl(targetId: targetId),
                                const SizedBox(width: AleraTokens.space6),
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: _CodexComposerControls(
                                      modelMenu: _modelMenu,
                                      reasoningMenu: _reasoningMenu,
                                      state: widget.state,
                                      onModelChanged: widget.onModelChanged,
                                      onReasoningChanged:
                                          widget.onReasoningChanged,
                                      onSpeedChanged: widget.onSpeedChanged,
                                      onPermissionChanged:
                                          widget.onPermissionChanged,
                                      onPlanChanged: widget.onPlanChanged,
                                      onCollaborationChanged:
                                          widget.onCollaborationChanged,
                                      onAddAttachment: widget.onAddAttachment,
                                      onPaste: widget.onPaste,
                                      onDraftItemSelected:
                                          widget.onDraftItemSelected,
                                      onCommand: widget.onCommand,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AleraTokens.space6),
                                IconButton(
                                  key: const ValueKey<String>(
                                    'composer-action-button',
                                  ),
                                  onPressed: widget.interrupting
                                      ? null
                                      : showSend
                                      ? (canSubmit ? widget.onSend : null)
                                      : () => unawaited(widget.onStop()),
                                  style: IconButton.styleFrom(
                                    backgroundColor: canSubmit || widget.busy
                                        ? AleraTokens.accent
                                        : AleraTokens.surface,
                                    foregroundColor: canSubmit || widget.busy
                                        ? AleraTokens.onAccent
                                        : AleraTokens.foregroundFaint,
                                    shape: const CircleBorder(),
                                  ),
                                  icon: widget.interrupting
                                      ? const SizedBox.square(
                                          dimension: AleraTokens.iconMd,
                                          child: CircularProgressIndicator(
                                            strokeWidth:
                                                AleraTokens.strokeIndicator,
                                            color: AleraTokens.onAccent,
                                          ),
                                        )
                                      : Icon(
                                          showSend
                                              ? AleraIcons.arrowUp
                                              : AleraIcons.stop,
                                          size: showSend
                                              ? AleraTokens.iconLg
                                              : AleraTokens.iconXl,
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (contextUsed != null &&
                      contextLimit != null &&
                      contextUsed > 0 &&
                      contextLimit > 0)
                    Positioned(
                      top: AleraTokens.space8,
                      right: AleraTokens.space12,
                      child: _CodexContextUsageIndicator(
                        used: contextUsed,
                        limit: contextLimit,
                        onCompact: () =>
                            widget.onCommand(CodexComposerCommand.compact),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
