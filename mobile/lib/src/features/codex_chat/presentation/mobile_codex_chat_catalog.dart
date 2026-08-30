part of 'mobile_codex_chat_screen.dart';

class const _MobileComposerCatalog({
  super.key,
  required final TextEditingController textController,
  required final MobileCodexController chatController,
  required final MobileCodexState state,
  required final String workspaceId,
  required final ValueChanged<Map<String, Object?>> onAddAttachment,
  required final ValueChanged<Map<String, Object?>> onCatalogSelection,
}) extends StatefulWidget {
  @override
  State<_MobileComposerCatalog> createState() => _MobileComposerCatalogState();
}

class _MobileComposerCatalogState extends State<_MobileComposerCatalog> {
  final ScrollController _scroll = ScrollController();
  List<_MobileCatalogItem> _items = const <_MobileCatalogItem>[];
  List<MobileCodexSavedPrompt> _prompts = const <MobileCodexSavedPrompt>[];
  MobileWorkspaceQuickOpenSession? _quickOpen;
  Future<MobileWorkspaceQuickOpenSession>? _quickOpenStart;
  Timer? _debounce;
  var _selected = 0;
  var _generation = 0;
  var _sessionEpoch = 0;
  var _promptsGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.textController.addListener(_refresh);
    unawaited(_loadPrompts());
  }

  @override
  void didUpdateWidget(covariant _MobileComposerCatalog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.textController != widget.textController) {
      oldWidget.textController.removeListener(_refresh);
      widget.textController.addListener(_refresh);
    }
    if (!identical(oldWidget.state.skills, widget.state.skills) ||
        !identical(oldWidget.state.apps, widget.state.apps)) {
      _refresh();
    }
    if (oldWidget.state.activeCwd != widget.state.activeCwd) {
      _sessionEpoch++;
      final session = _quickOpen;
      _quickOpen = null;
      _quickOpenStart = null;
      if (session != null) {
        unawaited(
          _stopMobileWorkspaceQuickOpen(widget.chatController, session),
        );
      }
      unawaited(_loadPrompts());
      _refresh();
    }
  }

  @override
  void dispose() {
    widget.textController.removeListener(_refresh);
    _debounce?.cancel();
    _sessionEpoch++;
    final session = _quickOpen;
    if (session != null) {
      unawaited(_stopMobileWorkspaceQuickOpen(widget.chatController, session));
    }
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadPrompts() async {
    final generation = ++_promptsGeneration;
    if (!widget.chatController.supportsWorkspaceFiles) {
      _prompts = const <MobileCodexSavedPrompt>[];
      return;
    }
    try {
      final prompts = await widget.chatController.listSavedPrompts(
        widget.workspaceId,
        cwd: widget.state.activeCwd,
      );
      if (!mounted || generation != _promptsGeneration) return;
      _prompts = prompts;
      _refresh();
    } on Object catch (error, stackTrace) {
      _MobileCodexChatScreenState._logger.warning(
        'Could not load saved Codex prompts.',
        error,
        stackTrace,
      );
      if (!mounted || generation != _promptsGeneration) return;
      _prompts = const <MobileCodexSavedPrompt>[];
      _refresh();
    }
  }

  void _refresh() {
    final token = _mobileComposerToken(widget.textController);
    if (token == null) {
      _invalidateWorkspaceSearch();
      _setItems(const <_MobileCatalogItem>[]);
      return;
    }
    if (token.prefix == r'$') {
      _invalidateWorkspaceSearch();
      final query = token.query.toLowerCase();
      _setItems(<_MobileCatalogItem>[
        for (final item in widget.state.skills)
          if (_mobileCatalogName(item).toLowerCase().contains(query))
            _MobileCatalogItem(
              title: _mobileCatalogName(item),
              subtitle: item['description']?.toString() ?? 'Skill',
              iconUrl: _mobileCatalogIcon(item),
              replacement: '\$${_mobileCatalogName(item)}',
              kind: 'Skill',
              catalogInput: _mobileSkillCatalogInput(item),
            ),
        for (final item in widget.state.apps)
          if (_mobileCatalogName(item).toLowerCase().contains(query))
            _MobileCatalogItem(
              title: _mobileCatalogName(item),
              subtitle: item['description']?.toString() ?? 'App',
              iconUrl: _mobileCatalogIcon(item),
              replacement: '\$${_mobileCatalogName(item)}',
              kind: 'App',
              catalogInput: _mobileAppCatalogInput(item),
            ),
      ]);
      return;
    }
    if (token.prefix == '/') {
      _invalidateWorkspaceSearch();
      final query = token.query.toLowerCase();
      final builtIns = <_MobileCatalogItem>[
        if (widget.chatController.supportsGoals)
          const _MobileCatalogItem(
            title: 'Goal',
            subtitle: 'Set or manage a long-running goal.',
            replacement: '/goal ',
            kind: 'Command',
          ),
        if (widget
            .chatController
            .supportsSessions) ...const <_MobileCatalogItem>[
          _MobileCatalogItem(
            title: 'Resume',
            subtitle: 'Resume an existing Codex thread.',
            replacement: '/resume',
            kind: 'Command',
          ),
          _MobileCatalogItem(
            title: 'New',
            subtitle: 'Start a new thread in this tab.',
            replacement: '/new',
            kind: 'Command',
          ),
          _MobileCatalogItem(
            title: 'Clear',
            subtitle: 'Clear the timeline and start a new thread.',
            replacement: '/clear',
            kind: 'Command',
          ),
        ],
        const _MobileCatalogItem(
          title: 'Rename',
          subtitle: 'Rename this Codex thread.',
          replacement: '/rename ',
          kind: 'Command',
        ),
        const _MobileCatalogItem(
          title: 'Compact',
          subtitle: 'Compact this chat context.',
          replacement: '/compact',
          kind: 'Command',
        ),
        const _MobileCatalogItem(
          title: 'Review',
          subtitle: 'Start a code review.',
          replacement: '/review',
          kind: 'Command',
        ),
      ];
      final savedPromptNames = <String>{
        for (final prompt in _prompts) prompt.name.toLowerCase(),
      };
      _setItems(<_MobileCatalogItem>[
        for (final item in builtIns)
          if (item.title.toLowerCase().contains(query) &&
              !savedPromptNames.contains(item.title.toLowerCase()))
            item,
        for (final prompt in _prompts)
          if (prompt.name.toLowerCase().contains(query))
            _MobileCatalogItem(
              title: prompt.name,
              subtitle: prompt.description,
              replacement: '/${prompt.name} ',
              kind: 'Prompt',
            ),
      ]);
      return;
    }
    _debounce?.cancel();
    final generation = ++_generation;
    _setItems(const <_MobileCatalogItem>[]);
    if (!widget.chatController.supportsWorkspaceFiles) return;
    _debounce = Timer(const Duration(milliseconds: 180), () {
      unawaited(_searchWorkspace(token.query, generation));
    });
  }

  void _invalidateWorkspaceSearch() {
    _debounce?.cancel();
    _debounce = null;
    _generation++;
  }

  Future<void> _searchWorkspace(String query, int generation) async {
    MobileWorkspaceQuickOpenSession? searchedSession;
    try {
      final epoch = _sessionEpoch;
      final session = await _ensureQuickOpen(epoch);
      if (session == null) return;
      searchedSession = session;
      final matches = await widget.chatController.searchWorkspaceQuickOpen(
        session,
        query,
      );
      if (!mounted || generation != _generation) return;
      _setItems(<_MobileCatalogItem>[
        for (final match in matches)
          _MobileCatalogItem(
            title: match.relativePath,
            subtitle: 'Workspace File',
            replacement: match.relativePath,
            kind: 'File',
            isWorkspaceFile: true,
          ),
      ]);
    } on Object catch (error, stackTrace) {
      _MobileCodexChatScreenState._logger.warning(
        'Codex workspace Quick Open failed.',
        error,
        stackTrace,
      );
      final session = searchedSession;
      if (generation == _generation &&
          session != null &&
          identical(_quickOpen, session)) {
        _quickOpen = null;
        unawaited(
          _stopMobileWorkspaceQuickOpen(widget.chatController, session),
        );
      }
      if (mounted && generation == _generation) {
        _setItems(const <_MobileCatalogItem>[]);
      }
    }
  }

  Future<MobileWorkspaceQuickOpenSession?> _ensureQuickOpen(int epoch) async {
    final existing = _quickOpen;
    if (existing != null) return existing;
    final start = _quickOpenStart ??= widget.chatController
        .startWorkspaceQuickOpen(
          widget.workspaceId,
          cwd: widget.state.activeCwd,
        );
    try {
      final session = await start;
      if (!mounted || epoch != _sessionEpoch) {
        await _stopMobileWorkspaceQuickOpen(widget.chatController, session);
        return null;
      }
      _quickOpen = session;
      return session;
    } finally {
      if (identical(_quickOpenStart, start)) _quickOpenStart = null;
    }
  }

  void _setItems(List<_MobileCatalogItem> items) {
    if (!mounted) return;
    setState(() {
      _items = List<_MobileCatalogItem>.unmodifiableOf(items);
      _selected = _items.isEmpty ? 0 : _selected.clamp(0, _items.length - 1);
    });
  }

  bool moveSelection(int delta) {
    if (_items.isEmpty) return false;
    setState(() {
      _selected = (_selected + delta).clamp(0, _items.length - 1);
    });
    if (!_scroll.hasClients) return true;
    final target = _selected * AleraTokens.codexCatalogRowHeight;
    unawaited(
      _scroll.animateTo(
        target.clamp(0, _scroll.position.maxScrollExtent),
        duration: AleraTokens.durationFast,
        curve: Curves.easeOut,
      ),
    );
    return true;
  }

  bool acceptSelection() {
    if (_items.isEmpty) return false;
    _select(_items[_selected]);
    return true;
  }

  void _select(_MobileCatalogItem item) {
    final token = _mobileComposerToken(widget.textController);
    if (token == null) return;
    if (item.isWorkspaceFile) {
      widget.onAddAttachment(<String, Object?>{
        'type': 'mention',
        'origin': 'mention',
        'name': _mobileBaseName(item.replacement),
        'path': item.replacement,
        if (widget.state.activeCwd?.trim().isNotEmpty == true)
          'cwd': widget.state.activeCwd!.trim(),
      });
      _replaceComposerToken(
        widget.textController,
        token,
        '${mobileCodexFileReferenceText(item.replacement)} ',
      );
    } else if (item.catalogInput case final input?) {
      _replaceComposerToken(
        widget.textController,
        token,
        '${item.replacement} ',
      );
      widget.onCatalogSelection(
        mobileCodexTrackCatalogSelection(input, tokenStart: token.start),
      );
    } else {
      _replaceComposerToken(widget.textController, token, item.replacement);
    }
    _setItems(const <_MobileCatalogItem>[]);
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final height =
        (_items.length.clamp(1, AleraTokens.codexCatalogVisibleRowCount) *
                AleraTokens.codexCatalogRowHeight)
            .toDouble();
    return Container(
      height: height,
      margin: const EdgeInsets.only(bottom: AleraTokens.space6),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.border),
      ),
      clipBehavior: .antiAlias,
      child: ListView.builder(
        controller: _scroll,
        itemExtent: AleraTokens.codexCatalogRowHeight,
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          return Material(
            type: .transparency,
            child: ListTile(
              selected: index == _selected,
              selectedTileColor: AleraTokens.surfaceVariant,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
              ),
              leading: _MobileCatalogIcon(item: item),
              title: Text(item.title, maxLines: 1, overflow: .ellipsis),
              subtitle: Text(item.subtitle, maxLines: 1, overflow: .ellipsis),
              trailing: Text(item.kind),
              onTap: () => _select(item),
            ),
          );
        },
      ),
    );
  }
}
