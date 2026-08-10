part of 'codex_chat_surface.dart';

extension _CodexComposerQuickOpen on _CodexComposerState {
  Future<void> _restartQuickOpen(String workspacePath, int generation) async {
    await _stopQuickOpen();
    if (!mounted || generation != _quickOpenGeneration) return;
    await _startQuickOpen(workspacePath, generation);
  }

  Future<void> _refreshQuickOpen() async {
    final workspacePath = widget.workspacePath;
    final active = _quickOpenRefresh;
    if (active != null && _quickOpenRefreshPath == workspacePath) return active;
    final operation = _restartQuickOpen(workspacePath, _quickOpenGeneration);
    _quickOpenRefresh = operation;
    _quickOpenRefreshPath = workspacePath;
    try {
      await operation;
    } finally {
      if (identical(_quickOpenRefresh, operation)) {
        _quickOpenRefresh = null;
        _quickOpenRefreshPath = null;
      }
    }
  }

  Future<void> _stopQuickOpen() async {
    final previous = _quickOpenSession;
    _quickOpenSession = null;
    if (previous == null) return;
    try {
      await widget.workspaceFiles.stopQuickOpenSession(session: previous);
    } catch (_) {}
  }

  Future<void> _startQuickOpen(String workspacePath, int generation) async {
    try {
      final session = await widget.workspaceFiles.startQuickOpenSession(
        workspacePath: workspacePath,
      );
      if (!mounted ||
          generation != _quickOpenGeneration ||
          workspacePath != widget.workspacePath) {
        await widget.workspaceFiles.stopQuickOpenSession(session: session);
        return;
      }
      _quickOpenSession = session;
    } catch (_) {}
  }

  void _onTextChanged() {
    if (!_applyingHistory) {
      _historyIndex = null;
      _historyDraft = null;
    }
    final hasText = widget.controller.text.isNotEmpty;
    if (hasText != _hasText) {
      _setComposerState(() => _hasText = hasText);
    }
    _queryDebounce?.cancel();
    _queryDebounce = Timer(AleraTokens.durationFast, _updateOverlay);
  }

  Future<void> _updateOverlay() async {
    if (_disabled) {
      _clearOverlay();
      return;
    }
    final generation = ++_queryGeneration;
    final cursor = widget.controller.selection.baseOffset;
    if (cursor < 0 || cursor > widget.controller.text.length) {
      _clearOverlay();
      return;
    }
    final beforeCursor = widget.controller.text.substring(0, cursor);
    final slash = RegExp(r'^/(\S*)$').firstMatch(beforeCursor);
    if (slash != null) {
      final query = (slash.group(1) ?? '').toLowerCase();
      _setComposerState(() {
        _mentionFiles = const <String>[];
        _catalogItems = const <CodexDraftItem>[];
        _commands = codexComposerEntries(
          widget.savedPrompts,
          supportsSessions: widget.state.supportsSessions,
        ).where((command) => command.matches(query)).toList(growable: false);
        _selectedIndex = 0;
      });
      return;
    }
    final catalog = RegExp(r'\$(\S*)$').firstMatch(beforeCursor);
    if (catalog != null) {
      final query = (catalog.group(1) ?? '').toLowerCase();
      final items = <CodexDraftItem>[
        for (final skill in widget.state.skills)
          if (_catalogSearchText(skill).contains(query) &&
              skill['path']?.toString().trim().isNotEmpty == true)
            CodexDraftItem(
              id: 'skill-${skill['path']}',
              kind: CodexDraftItemKind.skill,
              name: _catalogName(skill),
              path: skill['path'].toString(),
              tokenText: '\$${_catalogName(skill)}',
            ),
        for (final app in widget.state.apps)
          if (_catalogSearchText(app).contains(query) &&
              _catalogConnector(app) != null)
            CodexDraftItem(
              id: 'app-${_catalogConnector(app)}',
              kind: CodexDraftItemKind.app,
              name: _catalogName(app),
              path: _catalogConnector(app)!,
              tokenText: '\$${_catalogName(app)}',
              iconUrl: _catalogIconUrl(app),
            ),
      ];
      _setComposerState(() {
        _commands = const <CodexComposerEntry>[];
        _mentionFiles = const <String>[];
        _catalogItems = items;
        _selectedIndex = 0;
      });
      return;
    }
    final mention = RegExp(r'@(\S*)$').firstMatch(beforeCursor);
    if (mention == null) {
      _clearOverlay();
      return;
    }
    final firstActivation = !_mentionActive;
    if (firstActivation) _mentionActive = true;
    if (firstActivation || _quickOpenSession == null) {
      await _refreshQuickOpen();
      if (!mounted || generation != _queryGeneration || _disabled) return;
    }
    if (!_mentionActive) return;
    final session = _quickOpenSession;
    if (session == null) {
      _clearOverlay();
      return;
    }
    try {
      final matches = await widget.workspaceFiles.searchQuickOpenSession(
        session: session,
        query: mention.group(1) ?? '',
        limit: 20,
      );
      if (!mounted || generation != _queryGeneration) return;
      _setComposerState(() {
        _commands = const <CodexComposerEntry>[];
        _catalogItems = const <CodexDraftItem>[];
        _mentionFiles = matches
            .map((match) => match.relativePath)
            .toList(growable: false);
        _selectedIndex = 0;
      });
    } catch (_) {
      if (mounted && generation == _queryGeneration) _clearOverlay();
    }
  }

  void _clearOverlay() {
    ++_queryGeneration;
    _mentionActive = false;
    if (_commands.isEmpty && _mentionFiles.isEmpty && _catalogItems.isEmpty) {
      return;
    }
    _setComposerState(() {
      _commands = const <CodexComposerEntry>[];
      _mentionFiles = const <String>[];
      _catalogItems = const <CodexDraftItem>[];
      _selectedIndex = 0;
    });
  }
}

String _catalogSearchText(Map<String, Object?> item) =>
    '${_catalogName(item)} ${_catalogDescription(item)} ${_catalogScope(item)}'
        .toLowerCase();
