part of 'codex_chat_surface.dart';

class _CodexComposer extends StatefulWidget {
  const _CodexComposer({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.interrupting,
    required this.mcpInitializing,
    required this.blockedMessage,
    required this.attachments,
    required this.draftItems,
    required this.savedPrompts,
    required this.state,
    required this.promptHistory,
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
    required this.onDropAttachments,
    required this.onRemoveAttachment,
    required this.onOpenAttachment,
    required this.onRemoveDraftItem,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final bool interrupting;
  final bool mcpInitializing;
  final String? blockedMessage;
  final List<CodexInputAttachment> attachments;
  final List<CodexDraftItem> draftItems;
  final List<native.CodexSavedPrompt> savedPrompts;
  final CodexChatState state;
  final List<String> promptHistory;
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
  final Future<void> Function(
    Iterable<String> paths, {
    CodexInputAttachmentOrigin origin,
    String? tokenText,
    int? tokenStart,
  })
  onDropAttachments;
  final ValueChanged<CodexInputAttachment> onRemoveAttachment;
  final Future<void> Function(String path, {required bool isImage})
  onOpenAttachment;
  final ValueChanged<CodexDraftItem> onRemoveDraftItem;

  @override
  State<_CodexComposer> createState() => _CodexComposerState();
}

class _CodexComposerState extends State<_CodexComposer> {
  Timer? _queryDebounce;
  final ScrollController _composerScrollController = ScrollController();
  native.WorkspaceQuickOpenSession? _quickOpenSession;
  Future<void>? _quickOpenRefresh;
  String? _quickOpenRefreshPath;
  List<String> _mentionFiles = const <String>[];
  List<CodexComposerEntry> _commands = const <CodexComposerEntry>[];
  List<CodexDraftItem> _catalogItems = const <CodexDraftItem>[];
  int _selectedIndex = 0;
  int _queryGeneration = 0;
  int _quickOpenGeneration = 0;
  bool _hasText = false;
  bool _mentionActive = false;
  int? _historyIndex;
  String? _historyDraft;
  bool _applyingHistory = false;

  bool get _disabled => widget.mcpInitializing || widget.blockedMessage != null;

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
      _quickOpenGeneration += 1;
      _queryGeneration += 1;
      _mentionActive = false;
      _mentionFiles = const <String>[];
      unawaited(_stopQuickOpen());
    }
    final wasDisabled =
        oldWidget.mcpInitializing || oldWidget.blockedMessage != null;
    if (!wasDisabled && _disabled) {
      widget.focusNode.unfocus();
      _queryDebounce?.cancel();
      _queryGeneration += 1;
      _mentionActive = false;
      _commands = const <CodexComposerEntry>[];
      _mentionFiles = const <String>[];
      _catalogItems = const <CodexDraftItem>[];
      unawaited(_stopQuickOpen());
    }
  }

  @override
  void dispose() {
    _queryDebounce?.cancel();
    _composerScrollController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final contextUsed = widget.state.snapshot.contextUsed;
    final contextLimit = widget.state.snapshot.contextLimit;
    final canSubmit =
        !_disabled &&
        (_hasText ||
            widget.attachments.isNotEmpty ||
            widget.draftItems.isNotEmpty);
    return DragTarget<TerminalPathDragPayload>(
      onWillAcceptWithDetails: (_) => !widget.interrupting && !_disabled,
      onAcceptWithDetails: (details) =>
          unawaited(widget.onDropAttachments(details.data.paths)),
      builder: (context, _, _) => Center(
        key: const ValueKey<String>('codex-composer'),
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
                if (_catalogItems.isNotEmpty)
                  _CodexCatalogOverlay(
                    items: _catalogItems,
                    selectedIndex: _selectedIndex,
                    onSelected: _selectCatalogItem,
                  ),
                AiDictationTarget(
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  initialPrompt:
                      'The user is chatting with Codex about a software task.',
                  builder: (context, targetId) => Stack(
                    children: <Widget>[
                      AbsorbPointer(
                        absorbing: _disabled,
                        child: DecoratedBox(
                          key: const ValueKey<String>('codex-composer-shell'),
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
                                onOpen: (item) => widget.onOpenAttachment(
                                  item.path,
                                  isImage: false,
                                ),
                              ),
                              _CodexAttachmentBar(
                                attachments: widget.attachments,
                                draftItems: widget.draftItems,
                                onRemoveAttachment: widget.onRemoveAttachment,
                                onRemoveDraftItem: widget.onRemoveDraftItem,
                                onOpen: widget.onOpenAttachment,
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
                                child: Scrollbar(
                                  controller: _composerScrollController,
                                  thumbVisibility: true,
                                  child: ScrollConfiguration(
                                    behavior: ScrollConfiguration.of(
                                      context,
                                    ).copyWith(scrollbars: false),
                                    child: TextField(
                                      key: const ValueKey<String>(
                                        'codex-composer-text-field',
                                      ),
                                      controller: widget.controller,
                                      scrollController:
                                          _composerScrollController,
                                      focusNode: widget.focusNode,
                                      enabled:
                                          !widget.interrupting && !_disabled,
                                      minLines: 2,
                                      maxLines: 6,
                                      textInputAction: TextInputAction.newline,
                                      decoration: const InputDecoration(
                                        hintText:
                                            'Ask Codex anything, @ for files, \$ for skills and apps, / for commands',
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
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AleraTokens.space8,
                                  0,
                                  AleraTokens.space8,
                                  AleraTokens.space6,
                                ),
                                child: Row(
                                  key: const ValueKey<String>(
                                    'codex-composer-controls-row',
                                  ),
                                  children: <Widget>[
                                    Expanded(
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: _CodexComposerControls(
                                          state: widget.state,
                                          onPermissionChanged:
                                              widget.onPermissionChanged,
                                          onPlanChanged: widget.onPlanChanged,
                                          onAddAttachment:
                                              widget.onAddAttachment,
                                          onPaste: widget.onPaste,
                                          onDraftItemSelected:
                                              widget.onDraftItemSelected,
                                          onCommand: widget.onCommand,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: AleraTokens.space6),
                                    Flexible(
                                      fit: FlexFit.loose,
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: <Widget>[
                                            if (contextUsed != null &&
                                                contextLimit != null &&
                                                contextUsed > 0 &&
                                                contextLimit > 0) ...<Widget>[
                                              _CodexContextUsageIndicator(
                                                used: contextUsed,
                                                limit: contextLimit,
                                                onCompact: () =>
                                                    widget.onCommand(
                                                      CodexComposerCommand
                                                          .compact,
                                                    ),
                                              ),
                                              const SizedBox(
                                                width: AleraTokens.space2,
                                              ),
                                            ],
                                            Flexible(
                                              child:
                                                  _CodexModelConfigurationControl(
                                                    state: widget.state,
                                                    onModelChanged:
                                                        widget.onModelChanged,
                                                    onReasoningChanged: widget
                                                        .onReasoningChanged,
                                                    onSpeedChanged:
                                                        widget.onSpeedChanged,
                                                    onCollaborationChanged: widget
                                                        .onCollaborationChanged,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: AleraTokens.space2),
                                    AiDictationControl(
                                      key: const ValueKey<String>(
                                        'codex-dictation-control',
                                      ),
                                      targetId: targetId,
                                    ),
                                    const SizedBox(width: AleraTokens.space2),
                                    _buildActionButton(canSubmit: canSubmit),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_disabled)
                        Positioned.fill(
                          child: DecoratedBox(
                            key: const ValueKey<String>(
                              'codex-composer-mcp-loading',
                            ),
                            decoration: BoxDecoration(
                              color: AleraTokens.codexComposerDisabledOverlay,
                              borderRadius: BorderRadius.circular(
                                AleraTokens.radiusXl,
                              ),
                            ),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    widget.mcpInitializing
                                        ? AleraIcons.host
                                        : AleraIcons.warning,
                                    size: AleraTokens.iconMd,
                                    color: AleraTokens.foregroundMuted,
                                  ),
                                  const SizedBox(width: AleraTokens.space8),
                                  if (widget.mcpInitializing)
                                    _CodexShimmerText(
                                      text: 'Initializing MCP servers...',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: AleraTokens.foregroundMuted,
                                          ),
                                    )
                                  else
                                    Text(
                                      widget.blockedMessage!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: AleraTokens.foregroundMuted,
                                          ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
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
