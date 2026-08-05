part of 'codex_chat_surface.dart';

extension _CodexComposerQuickOpen on _CodexComposerState {
  Future<void> _restartQuickOpen() async {
    await _stopQuickOpen();
    await _startQuickOpen();
  }

  Future<void> _refreshQuickOpen() async {
    final active = _quickOpenRefresh;
    if (active != null) return active;
    final operation = _restartQuickOpen();
    _quickOpenRefresh = operation;
    try {
      await operation;
    } finally {
      if (identical(_quickOpenRefresh, operation)) _quickOpenRefresh = null;
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

  Future<void> _startQuickOpen() async {
    try {
      final session = await widget.workspaceFiles.startQuickOpenSession(
        workspacePath: widget.workspacePath,
      );
      if (!mounted) {
        await widget.workspaceFiles.stopQuickOpenSession(session: session);
        return;
      }
      _quickOpenSession = session;
    } catch (_) {}
  }

  void _onTextChanged() {
    final hasText = widget.controller.text.isNotEmpty;
    if (hasText != _hasText) {
      _setComposerState(() => _hasText = hasText);
    }
    _queryDebounce?.cancel();
    _queryDebounce = Timer(AleraTokens.durationFast, _updateOverlay);
  }

  Future<void> _updateOverlay() async {
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
        _commands = codexComposerEntries(
          widget.savedPrompts,
        ).where((command) => command.matches(query)).toList(growable: false);
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
      if (!mounted) return;
    }
    if (!_mentionActive) return;
    final session = _quickOpenSession;
    if (session == null) {
      _clearOverlay();
      return;
    }
    final generation = ++_queryGeneration;
    try {
      final matches = await widget.workspaceFiles.searchQuickOpenSession(
        session: session,
        query: mention.group(1) ?? '',
        limit: 20,
      );
      if (!mounted || generation != _queryGeneration) return;
      _setComposerState(() {
        _commands = const <CodexComposerEntry>[];
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
    if (_commands.isEmpty && _mentionFiles.isEmpty) return;
    _setComposerState(() {
      _commands = const <CodexComposerEntry>[];
      _mentionFiles = const <String>[];
      _selectedIndex = 0;
    });
  }
}
