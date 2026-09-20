part of 'terminal_tab_view.dart';

class const _TerminalSurface({
  super.key,
  required final TerminalTabSession session,
  required final TerminalInputMode inputMode,
  required final bool allowOsc52Clipboard,
  required final ValueChanged<String> onInput,
  required final void Function(int cols, int rows) onViewportResize,
  required final Future<void> Function() onReconnect,
}) extends StatefulWidget {
  @override
  State<_TerminalSurface> createState() => _TerminalSurfaceState();
}

class _TerminalSurfaceState extends State<_TerminalSurface> {
  late Terminal _terminal;
  final TerminalController _controller = TerminalController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode(debugLabel: 'MobileTerminal');
  final ValueNotifier<TerminalRestoreProgress?> _restoreProgress =
      ValueNotifier<TerminalRestoreProgress?>(null);
  // Its own notifier so the pill toggles without rebuilding the terminal view.
  final ValueNotifier<bool> _awayFromLatest = ValueNotifier<bool>(false);
  TerminalOutputBatcher? _batcher;
  StreamSubscription<MobileTerminalOutputEvent>? _outputSub;
  bool _outputEnded = false;
  int _viewGeneration = 0;
  // Replaced together with the generation, which remounts the view.
  GlobalKey<TerminalViewState> _viewKey = GlobalKey<TerminalViewState>();
  (int, int)? _suppressedViewportSize;
  bool _ignoreViewportResize = false;
  bool _osc52BlockedNoticeShown = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateAwayFromLatest);
    _bindSession(widget.session, notify: false);
  }

  @override
  void didUpdateWidget(_TerminalSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The session id is stable across re-attaches, so this State survives a
    // reconnect that hands down a new session over a new client. Without
    // rebinding, the subscription stays on the previous client's closed stream
    // and the terminal freezes on whatever it had drawn.
    if (!identical(oldWidget.session, widget.session)) {
      _bindSession(widget.session, notify: true);
    }
  }

  @override
  void dispose() {
    unawaited(_outputSub?.cancel());
    _batcher?.dispose();
    _terminal.removeListener(_updateAwayFromLatest);
    _terminal.dispose();
    _restoreProgress.dispose();
    _awayFromLatest.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// The pill shows while history sits between the reader and the live
  /// screen. An alternate-screen app has no such history: the app scrolls
  /// itself and the scroll controller has no position to read.
  void _updateAwayFromLatest() {
    if (!mounted) {
      return;
    }
    final away =
        !_terminal.isUsingAltBuffer &&
        _scrollController.hasClients &&
        _scrollController.position.hasContentDimensions &&
        _scrollController.position.maxScrollExtent - _scrollController.offset >
            _lineHeight * terminalJumpToLatestThresholdLines;
    _awayFromLatest.value = away;
  }

  double get _lineHeight {
    final state = _viewKey.currentState;
    if (state == null || !(_viewKey.currentContext?.mounted ?? false)) {
      return AleraTokens.monoFontSize;
    }
    return state.renderTerminal.lineHeight;
  }

  void scrollToLatest() {
    if (!_scrollController.hasClients) {
      return;
    }
    final position = _scrollController.position;
    if (!position.hasContentDimensions) {
      return;
    }
    unawaited(
      _scrollController.animateTo(
        position.maxScrollExtent,
        duration: AleraTokens.durationMid,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _bindSession(TerminalTabSession session, {required bool notify}) {
    unawaited(_outputSub?.cancel());
    _outputSub = null;
    _outputEnded = false;
    _replaceEmulator(notify: notify);
    final snapshot = session.takeSnapshot();
    if (snapshot.isNotEmpty) {
      _restoreSnapshot(
        utf8.decode(snapshot, allowMalformed: true),
        cols: session.snapshotCols,
        rows: session.snapshotRows,
      );
    }
    _outputSub = session.output.listen(
      _handleOutput,
      // A closed or errored source is otherwise indistinguishable from a
      // terminal that simply has nothing to say.
      onError: (Object _, StackTrace _) => _markOutputEnded(),
      onDone: _markOutputEnded,
    );
  }

  /// Builds a fresh emulator rather than writing clear sequences into the old
  /// one, so alt-buffer, mouse reporting, and cursor modes reset too.
  void _replaceEmulator({required bool notify}) {
    final previous = _batcher == null ? null : _terminal;
    _batcher?.dispose();
    previous?.removeListener(_updateAwayFromLatest);
    _controller.clearSelection();
    final next = Terminal(
      maxLines: mobileTerminalScrollbackLines,
      preserveOrphanCombiningMarks: true,
      allowITerm2ClipboardCapture: false,
      allowKittyClipboard: false,
      // The agent runs on the paired machine, so a copy it makes for itself
      // (`pbcopy`, `xclip`) lands there and never reaches this phone. OSC 52
      // is the one path that does. Writes are gated by the same off-by-default
      // policy the desktop applies, read at write time so a settings change
      // reaches live sessions, and announced when allowed. Queries stay
      // unanswered: an unset callback would let TerminalView hand the phone's
      // clipboard to a remote program.
      onClipboardStore: (_, text) => _storeRemoteClipboardText(text),
      onClipboardQuery: (_) => null,
      clipboardDecoder: decodeTerminalOsc52Payload,
      onOutput: (data) => widget.onInput(data),
      onResize: (width, height, _, _) => _handleViewportResize(width, height),
      // This emulator is filled from restored history, and the program that
      // wrote it keeps the cursor hidden for as long as it runs. Without this
      // the resize down to the phone's width truncates every line of that
      // history instead of reflowing it, on the assumption that whoever hid
      // the cursor is about to redraw - which is true of the live screen and
      // false of everything scrolled above it.
      reflowWithHiddenCursor: true,
    );
    // One write per frame. Writing every chunk straight through made a noisy
    // build parse and repaint many times inside a single frame.
    _batcher = TerminalOutputBatcher(
      write: next.write,
      onRestoreProgress: _handleRestoreProgress,
    );
    // Entering or leaving the alternate screen changes who owns scrolling.
    next.addListener(_updateAwayFromLatest);
    previous?.dispose();
    if (notify) {
      setState(() => _terminal = next);
    } else {
      _terminal = next;
    }
  }

  void _storeRemoteClipboardText(String text) {
    if (!mounted || text.isEmpty) {
      return;
    }
    if (!widget.allowOsc52Clipboard) {
      _notifyOsc52Blocked();
      return;
    }
    unawaited(_copyToClipboard(text, notice: 'Agent copied to clipboard'));
  }

  /// Once per surface, so a program that retries does not flood the screen.
  void _notifyOsc52Blocked() {
    if (_osc52BlockedNoticeShown) {
      return;
    }
    _osc52BlockedNoticeShown = true;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text(
          'Terminal clipboard write blocked. Enable OSC 52 clipboard writes in Settings.',
        ),
      ),
    );
  }

  /// Long-press selects a word and dragging extends it; the pill is how a
  /// finger copies, since there is no Ctrl+C or context menu to reach for.
  void _copySelection() {
    final selection = _controller.selectionFor(_terminal.buffer);
    if (selection == null) {
      return;
    }
    final text = _terminal.buffer.getText(selection, true);
    _controller.clearSelection();
    if (text.isEmpty) {
      return;
    }
    unawaited(_copyToClipboard(text, notice: 'Copied to clipboard'));
  }

  Future<void> _copyToClipboard(String text, {required String notice}) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (error, stackTrace) {
      Logger('TerminalTabView')
          .warning('terminal clipboard copy failed', error, stackTrace);
      messenger?.showSnackBar(
        const SnackBar(content: Text('Could not copy to clipboard')),
      );
      return;
    }
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(notice)));
  }

  void _handleOutput(MobileTerminalOutputEvent event) {
    final text = utf8.decode(event.data, allowMalformed: true);
    if (event.replacesScrollback) {
      _replaceEmulator(notify: true);
      _restoreSnapshot(
        text,
        cols: event.snapshotCols,
        rows: event.snapshotRows,
      );
      return;
    }
    _batcher!.add(text);
  }

  /// Replays restored history at the size it was written at.
  ///
  /// The snapshot is the raw PTY stream, which only reconstructs the screen it
  /// came from at the geometry that produced it: every absolute cursor move and
  /// hard wrap in it is stated in those columns. Parsing it at the phone's much
  /// narrower width is what made the restored scrollback unreadable while the
  /// live screen below it looked fine, since the running program redrew that
  /// part itself. Replaying wide and then letting the view resize turns the
  /// difference into a reflow, which is the operation that preserves the text.
  ///
  /// The view stays unmounted until the last byte is in, so the resize that
  /// reflows happens once, against the whole history rather than a prefix.
  void _restoreSnapshot(String text, {required int? cols, required int? rows}) {
    if (cols != null && rows != null) {
      // The PTY is already this size; echoing it back would be a pointless
      // round trip, and a wrong one once the view states the real viewport.
      // Guard the callback rather than a one-shot expected size: a no-op
      // resize (already at this geometry) never fires onResize, and a stuck
      // expected size would swallow the phone's own viewport if it matched.
      _ignoreViewportResize = true;
      try {
        _terminal.resize(cols, rows);
      } finally {
        _ignoreViewportResize = false;
      }
    }
    _batcher!.addSnapshot(text);
  }

  void _handleRestoreProgress(TerminalRestoreProgress? progress) {
    if (!mounted) {
      return;
    }
    // Clearing this mounts the view, whose layout states the phone's viewport
    // and reflows the history that was just replayed at the host's.
    _restoreProgress.value = progress;
  }

  void _markOutputEnded() {
    if (!mounted || _outputEnded) {
      return;
    }
    setState(() => _outputEnded = true);
  }

  void _handleViewportResize(int width, int height) {
    if (_ignoreViewportResize) {
      return;
    }
    final suppressed = _suppressedViewportSize;
    _suppressedViewportSize = null;
    if (suppressed == (width, height)) {
      return;
    }
    widget.onViewportResize(width, height);
  }

  Future<void> refreshRendering() async {
    if (!mounted) {
      return;
    }
    final restoreFocus = _focusNode.hasFocus;
    _suppressedViewportSize = (_terminal.viewWidth, _terminal.viewHeight);
    setState(() {
      _viewGeneration += 1;
      _viewKey = GlobalKey<TerminalViewState>();
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && restoreFocus) {
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final direct = widget.inputMode == TerminalInputMode.direct;
    return Column(
      children: <Widget>[
        if (_outputEnded) _OutputEndedBanner(onReconnect: widget.onReconnect),
        Expanded(
          child: ColoredBox(
            color: AleraTokens.background,
            // Restoring a tab replays its whole scrollback over many frames.
            // The view is held back rather than covered: mounting it states
            // the phone's viewport, which would resize the emulator away from
            // the size the history is being replayed at, reflowing a prefix of
            // it and then fighting the rest.
            child: ValueListenableBuilder<TerminalRestoreProgress?>(
              valueListenable: _restoreProgress,
              builder: (context, progress, _) => progress != null
                  ? _TerminalRestoreState(progress: progress)
                  : Stack(
                      fit: .expand,
                      children: <Widget>[
                        _buildTerminalView(direct),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: AleraTokens.spaceMd,
                          child: Center(
                            child: Wrap(
                              spacing: AleraTokens.spaceSm,
                              children: <Widget>[
                                ListenableBuilder(
                                  listenable: _controller,
                                  builder: (context, _) => AnimatedSwitcher(
                                    duration: AleraTokens.durationMid,
                                    child: _controller.selection != null
                                        ? AleraFloatingPillButton(
                                            label: 'Copy',
                                            icon: AleraIcons.copy,
                                            onPressed: _copySelection,
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ),
                                ValueListenableBuilder<bool>(
                                  valueListenable: _awayFromLatest,
                                  builder: (context, away, _) =>
                                      AnimatedSwitcher(
                                        duration: AleraTokens.durationMid,
                                        child: away
                                            ? AleraFloatingPillButton(
                                                label: 'Jump To Latest',
                                                icon: AleraIcons.chevronDown,
                                                onPressed: scrollToLatest,
                                              )
                                            : const SizedBox.shrink(),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTerminalView(bool direct) {
    return TerminalView(
      _terminal,
      key: _viewKey,
      shortcuts: clipboardTerminalShortcuts,
      shiftOverridesMouseReporting: true,
      controller: _controller,
      scrollController: _scrollController,
      focusNode: _focusNode,
      // Compose mode keeps the terminal read-only so tapping it
      // does not raise the soft keyboard. Scroll routing is
      // independent of this: xterm sends wheel reports to an
      // alternate-screen or mouse-mode TUI either way, and
      // scrolls the cell buffer for inline transcripts.
      readOnly: !direct,
      touchScrollLinesPerWheelEvent: mobileTouchScrollLinesPerWheelEvent,
      autofocus: direct && _viewGeneration == 0,
      backgroundOpacity: 0,
      // OS font scale would change the cell size and therefore
      // the PTY cols/rows, which is what made agent TUIs draw
      // to a geometry that no longer matched the chrome.
      textScaler: TextScaler.noScaling,
      textStyle: const TerminalStyle(
        fontFamily: AleraTokens.monoFontFamily,
        fontSize: AleraTokens.monoFontSize,
      ),
      padding: const .all(AleraTokens.spaceSm),
    );
  }
}
