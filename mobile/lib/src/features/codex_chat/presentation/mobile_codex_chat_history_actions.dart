part of 'mobile_codex_chat_screen.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _MobileCodexHistoryActions on _MobileCodexChatScreenState {
  int? _findTimelineRowIndex(List<MobileCodexPresentationRow> rows, Key key) {
    if (key is! ValueKey<String>) return null;
    if (!identical(_timelineRowIndexSource, rows)) {
      _timelineRowIndexSource = rows;
      _timelineRowIndexes = <String, int>{
        for (var index = 0; index < rows.length; index += 1)
          rows[index].id: index,
      };
    }
    return _timelineRowIndexes[key.value];
  }

  void _handleTimelineScroll() {
    if (!_timeline.hasClients) return;
    if (_timeline.position.pixels <= AleraTokens.space48 && !_loadingEarlier) {
      final provider = mobileCodexControllerProvider(
        widget.hostId,
        widget.tabId,
      );
      final cursor = ref.read(provider).value?.historyNextCursor;
      if (cursor != null && cursor.isNotEmpty) {
        _loadingEarlier = true;
        unawaited(_loadEarlierHistory(ref.read(provider.notifier), cursor));
      }
    }
    final next = _timeline.position.extentAfter > AleraTokens.space48;
    _timelinePinned = !next;
    if (next != _showScrollToBottom && mounted) {
      setState(() => _showScrollToBottom = next);
    }
  }

  Future<void> _loadEarlierHistory(
    MobileCodexController controller,
    String cursor,
  ) async {
    _freezeTimelineForHistoryLoad();
    await WidgetsBinding.instance.endOfFrame;
    if (!_timeline.hasClients) {
      try {
        await controller.loadHistory(cursor: cursor);
      } finally {
        _finishLoadingEarlier();
      }
      return;
    }
    final previousOffset = _timeline.offset;
    final previousExtent = _timeline.position.maxScrollExtent;
    final previousAnchorTop = _historyAnchorTop;
    try {
      await controller.loadHistory(cursor: cursor);
      if (!mounted) return;
      _showHistoryRowsBeforeConcurrentAppends();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_timeline.hasClients) return;
      final nextAnchorTop = _historyAnchorTop;
      final scrollDelta = previousAnchorTop != null && nextAnchorTop != null
          ? nextAnchorTop - previousAnchorTop
          : _timeline.position.maxScrollExtent - previousExtent;
      final target = (previousOffset + scrollDelta)
          .clamp(
            _timeline.position.minScrollExtent,
            _timeline.position.maxScrollExtent,
          )
          .toDouble();
      _timeline.jumpTo(target);
    } finally {
      _finishLoadingEarlier();
    }
  }

  void _freezeTimelineForHistoryLoad() {
    if (_historyRowsOverride != null) return;
    final state = ref
        .read(mobileCodexControllerProvider(widget.hostId, widget.tabId))
        .value;
    final rows =
        state?.presentationRows ?? const <MobileCodexPresentationRow>[];
    _historyRowsOverride = rows;
    _historyOriginalCellIds = rows.expand(_historyRowCellIds).toSet();
    _historyAnchorCellId = rows.isEmpty
        ? null
        : _historyRowCellIds(rows.first).first;
    if (mounted) setState(() {});
  }

  void _showHistoryRowsBeforeConcurrentAppends() {
    final originalIds = _historyOriginalCellIds;
    if (originalIds == null) return;
    final state = ref
        .read(mobileCodexControllerProvider(widget.hostId, widget.tabId))
        .value;
    final rows =
        state?.presentationRows ?? const <MobileCodexPresentationRow>[];
    final firstOriginal = rows.indexWhere(
      (row) => _historyRowCellIds(row).any(originalIds.contains),
    );
    final next = <MobileCodexPresentationRow>[
      if (firstOriginal > 0) ...rows.take(firstOriginal),
      for (final row in rows)
        if (_historyRowCellIds(row).any(originalIds.contains)) row,
    ];
    if (mounted) {
      setState(
        () => _historyRowsOverride =
            List<MobileCodexPresentationRow>.unmodifiable(next),
      );
    }
  }

  Iterable<String> _historyRowCellIds(MobileCodexPresentationRow row) =>
      row.activityCells.isNotEmpty
      ? row.activityCells.map((cell) => cell.id)
      : <String>[row.cell?.id ?? row.id];

  bool _historyRowContainsAnchor(MobileCodexPresentationRow row) {
    final anchor = _historyAnchorCellId;
    return anchor != null && _historyRowCellIds(row).contains(anchor);
  }

  double? get _historyAnchorTop {
    final renderObject = _historyAnchorKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return null;
    return renderObject.localToGlobal(Offset.zero).dy;
  }

  void _finishLoadingEarlier() {
    if (mounted) {
      setState(() {
        _loadingEarlier = false;
        _historyRowsOverride = null;
        _historyOriginalCellIds = null;
        _historyAnchorCellId = null;
      });
    } else {
      _loadingEarlier = false;
      _historyRowsOverride = null;
      _historyOriginalCellIds = null;
      _historyAnchorCellId = null;
    }
  }

  void _scrollToBottom() => _scheduleTimelinePin(animate: true);

  Future<void> _openPlan(MobileCodexTimelineCell cell) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => _MobileExpandedPlanScreen(
            hostId: widget.hostId,
            tabId: widget.tabId,
            workspaceId: widget.workspaceId,
            cwd: ref
                .read(
                  mobileCodexControllerProvider(widget.hostId, widget.tabId),
                )
                .value
                ?.activeCwd,
            cellId: cell.id,
          ),
        ),
      );

  void _scheduleTimelinePin({bool animate = false}) {
    if (!_timeline.hasClients) return;
    _timelinePinned ??= _timeline.position.extentAfter <= AleraTokens.space48;
    if (!animate && _timelinePinned != true) return;
    _timelinePinRequested = true;
    _animateTimelinePin = _animateTimelinePin || animate;
    if (_timelinePinScheduled) return;
    _timelinePinScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_settleTimelinePin());
    });
  }

  Future<void> _settleTimelinePin() async {
    try {
      for (var attempt = 0; attempt < 6; attempt += 1) {
        if (!mounted || !_timeline.hasClients) return;
        final animate = _animateTimelinePin;
        _animateTimelinePin = false;
        _timelinePinRequested = false;
        if (_timelinePinned != true && !animate) return;
        final position = _timeline.position;
        final target = position.maxScrollExtent;
        if ((target - position.pixels).abs() >= AleraTokens.space2) {
          if (animate) {
            await _timeline.animateTo(
              target,
              duration: AleraTokens.durationMid,
              curve: Curves.easeOut,
            );
          } else {
            _timeline.jumpTo(target);
          }
        }
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !_timeline.hasClients) return;
        if (_timelinePinned != true) return;
        if (!_timelinePinRequested &&
            _timeline.position.extentAfter < AleraTokens.space2) {
          return;
        }
      }
    } finally {
      _timelinePinScheduled = false;
      if (mounted && _timelinePinRequested) {
        _scheduleTimelinePin(animate: _animateTimelinePin);
      }
    }
  }
}
