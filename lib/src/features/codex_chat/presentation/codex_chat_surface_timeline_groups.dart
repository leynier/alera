part of 'codex_chat_surface.dart';

class _CodexTimelineState extends State<_CodexTimeline>
    with SingleTickerProviderStateMixin {
  static const int _entryWidgetCacheLimit = 128;
  static const String _entryKeyPrefix = 'codex-timeline-entry:';

  final Set<String> _expandedWorkedTurns = <String>{};
  final Set<String> _collapsedWorkingTurns = <String>{};
  final Set<String> _expandedToolGroups = <String>{};
  final Set<String> _expandedToolActions = <String>{};
  Set<String> _overflowingPlanPreviewIds = <String>{};
  final LinkedHashMap<
    String,
    ({Object source, Widget widget, GlobalKey anchorKey})
  >
  _entryWidgets =
      LinkedHashMap<
        String,
        ({Object source, Widget widget, GlobalKey anchorKey})
      >();
  final GlobalKey _timelineViewportKey = GlobalKey();
  final GlobalKey<SelectionAreaState> _timelineSelectionAreaKey =
      GlobalKey<SelectionAreaState>();
  final GlobalKey<SelectionAreaState> _planSelectionAreaKey =
      GlobalKey<SelectionAreaState>();
  late final AnimationController _planFlight;
  late _CodexTimelineProjection _projection;
  List<CodexTimelineCell>? _frozenHistoryLiveCells;
  CodexTimelineCell? _flyingPlan;
  BuildContext? _planSourceContext;
  Rect? _planSourceRect;
  double? _planTimelineOffset;
  Future<void>? _planRestoreInFlight;
  bool _showScrollToBottom = false;
  bool _scrollToBottomScheduled = false;
  bool _scrollToBottomRequested = false;
  bool _animateScrollToBottom = false;
  bool _timelineHasSelection = false;
  String? _pinnedEntryKey;

  @override
  void initState() {
    super.initState();
    _projection = _CodexTimelineProjection.fromSnapshot(
      widget.snapshot,
      showRawLogs: widget.showRawLogs,
    );
    _planFlight = AnimationController(
      vsync: this,
      duration: AleraTokens.codexPlanFlightDuration,
      reverseDuration: AleraTokens.codexPlanFlightDuration,
    )..addStatusListener(_handlePlanFlightStatus);
    widget.timeline.addListener(_handleScroll);
    widget.planDecisionRevision.addListener(_restorePlan);
  }

  @override
  void didUpdateWidget(covariant _CodexTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    final timelineChanged =
        !identical(
          oldWidget.snapshot.timelineCells,
          widget.snapshot.timelineCells,
        ) ||
        !identical(
          oldWidget.snapshot.pendingRequests,
          widget.snapshot.pendingRequests,
        );
    if (timelineChanged && _timelineHasSelection) {
      _timelineSelectionAreaKey.currentState?.selectableRegion.clearSelection();
      _timelineHasSelection = false;
    }
    if (!oldWidget.loadingEarlier && widget.loadingEarlier) {
      _frozenHistoryLiveCells = List<CodexTimelineCell>.unmodifiable(
        _projection.live.sourceCells,
      );
    }
    if (!identical(oldWidget.snapshot, widget.snapshot) ||
        oldWidget.showRawLogs != widget.showRawLogs ||
        oldWidget.loadingEarlier != widget.loadingEarlier) {
      _projection = _CodexTimelineProjection.fromSnapshot(
        widget.snapshot,
        showRawLogs: widget.showRawLogs,
        previous: _projection,
        liveCellsOverride: widget.loadingEarlier
            ? _frozenHistoryLiveCells
            : null,
      );
      _entryWidgets.removeWhere(
        (key, _) => !_projection.entries.containsKey(key),
      );
      _collapsedWorkingTurns.retainWhere(
        (turnId) => turnId == widget.snapshot.activeTurnId,
      );
      final planIds = widget.snapshot.timelineCells
          .where((cell) => cell.kind == CodexTimelineKind.plan)
          .map((cell) => cell.id)
          .toSet();
      _overflowingPlanPreviewIds = _overflowingPlanPreviewIds.intersection(
        planIds,
      );
    }
    if (oldWidget.loadingEarlier && !widget.loadingEarlier) {
      _frozenHistoryLiveCells = null;
    }
    if (oldWidget.workspacePath != widget.workspacePath ||
        oldWidget.onOpenAttachment != widget.onOpenAttachment ||
        oldWidget.onApproval != widget.onApproval ||
        oldWidget.onElicitation != widget.onElicitation ||
        oldWidget.onReject != widget.onReject) {
      _entryWidgets.clear();
    }
    if (oldWidget.timeline != widget.timeline) {
      oldWidget.timeline.removeListener(_handleScroll);
      widget.timeline.addListener(_handleScroll);
    }
    if (oldWidget.planDecisionRevision != widget.planDecisionRevision) {
      oldWidget.planDecisionRevision.removeListener(_restorePlan);
      widget.planDecisionRevision.addListener(_restorePlan);
    }
    final flyingPlanId = _flyingPlan?.id;
    if (flyingPlanId != null) {
      CodexTimelineCell? updatedPlan;
      for (final cell in widget.snapshot.timelineCells.reversed) {
        if (cell.id == flyingPlanId) {
          updatedPlan = cell;
          break;
        }
      }
      if (updatedPlan == null) {
        _planFlight.stop();
        _flyingPlan = null;
        _planSourceContext = null;
        _planSourceRect = null;
        _planTimelineOffset = null;
        _planFlight.value = 0;
      } else {
        _flyingPlan = updatedPlan;
      }
    }
    if (timelineChanged && !_showScrollToBottom) {
      _scheduleScrollToBottom();
    }
  }

  @override
  void dispose() {
    widget.timeline.removeListener(_handleScroll);
    widget.planDecisionRevision.removeListener(_restorePlan);
    _planFlight.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!widget.timeline.hasClients) return;
    final show = widget.timeline.position.extentAfter > AleraTokens.space48;
    if (show != _showScrollToBottom) {
      setState(() => _showScrollToBottom = show);
    }
  }

  void _scrollToBottom() => _scheduleScrollToBottom(animate: true);

  void _restorePlan() => unawaited(restorePlanAndWait());

  Future<void> restorePlanAndWait() =>
      _planRestoreInFlight ??= _restorePlanSerialized();

  Future<void> _restorePlanSerialized() async {
    try {
      await _performPlanRestore();
    } finally {
      _planRestoreInFlight = null;
    }
  }

  Future<void> _performPlanRestore() async {
    if (_flyingPlan == null || !mounted) return;
    _timelineSelectionAreaKey.currentState?.selectableRegion.clearSelection();
    _planSelectionAreaKey.currentState?.selectableRegion.clearSelection();
    try {
      await _planFlight.reverse().orCancel;
    } on TickerCanceled {
      // The timeline can be disposed while the plan is returning to its card.
    }
  }

  void _toggleWorkedTurn(String turnId, {required bool working}) {
    setState(() {
      _entryWidgets.remove('turn-$turnId');
      final turns = working ? _collapsedWorkingTurns : _expandedWorkedTurns;
      if (!turns.add(turnId)) {
        turns.remove(turnId);
      }
    });
  }

  void _toggleToolGroup(String turnId, String groupId) {
    setState(() {
      _entryWidgets.remove('turn-$turnId');
      if (!_expandedToolGroups.add(groupId)) {
        _expandedToolGroups.remove(groupId);
      }
    });
  }

  void _toggleToolAction(String turnId, String actionId) {
    setState(() {
      _entryWidgets.remove('turn-$turnId');
      if (!_expandedToolActions.add(actionId)) {
        _expandedToolActions.remove(actionId);
      }
    });
  }

  void _handlePlanPreviewOverflow(String planId, {required bool overflowing}) {
    final next = Set<String>.of(_overflowingPlanPreviewIds);
    if (overflowing ? !next.add(planId) : !next.remove(planId)) return;
    setState(() => _overflowingPlanPreviewIds = next);
  }

  void _maximizePlan(CodexTimelineCell cell, BuildContext sourceContext) {
    final viewport =
        _timelineViewportKey.currentContext?.findRenderObject() as RenderBox?;
    final source = sourceContext.findRenderObject() as RenderBox?;
    if (viewport == null || source == null || !viewport.hasSize) return;
    final sourceOrigin = source.localToGlobal(.zero, ancestor: viewport);
    _planTimelineOffset = widget.timeline.hasClients
        ? widget.timeline.position.pixels
        : null;
    setState(() {
      _flyingPlan = cell;
      _planSourceContext = sourceContext;
      _planSourceRect = sourceOrigin & source.size;
    });
    unawaited(_planFlight.forward(from: 0));
  }

  Rect? _currentPlanSourceRect() {
    final viewport =
        _timelineViewportKey.currentContext?.findRenderObject() as RenderBox?;
    final sourceContext = _planSourceContext;
    if (sourceContext == null || !sourceContext.mounted) return null;
    final source = sourceContext.findRenderObject() as RenderBox?;
    if (viewport == null ||
        source == null ||
        !viewport.attached ||
        !source.attached ||
        !source.hasSize) {
      return null;
    }
    return source.localToGlobal(.zero, ancestor: viewport) & source.size;
  }

  void _handlePlanFlightStatus(AnimationStatus status) {
    if (status != AnimationStatus.dismissed ||
        _flyingPlan == null ||
        !mounted) {
      return;
    }
    setState(() {
      _flyingPlan = null;
      _planSourceContext = null;
      _planSourceRect = null;
    });
    final target = _planTimelineOffset;
    _planTimelineOffset = null;
    if (target == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.timeline.hasClients) return;
      widget.timeline.jumpTo(
        target.clamp(
          widget.timeline.position.minScrollExtent,
          widget.timeline.position.maxScrollExtent,
        ),
      );
    });
  }

  Widget _buildEntry(BuildContext context, int index) {
    final entry = _projection.entries[index];
    final cached = _entryWidgets.remove(entry.key);
    if (cached != null && identical(cached.source, entry.source)) {
      _entryWidgets[entry.key] = cached;
      return cached.widget;
    }
    final Widget child = switch (entry.kind) {
      _CodexTimelineEntryKind.cell => _CodexCellView(
        cell: entry.cell!,
        workspacePath: widget.workspacePath,
        onOpenAttachment: widget.onOpenAttachment,
      ),
      _CodexTimelineEntryKind.turn => _buildTurnEntry(entry.turn!),
      _CodexTimelineEntryKind.event => _CodexRawEvent(event: entry.event!),
      _CodexTimelineEntryKind.request =>
        entry.request!.isApproval
            ? _CodexApprovalCard(
                request: entry.request!,
                onApproval: widget.onApproval,
              )
            : entry.request!.isElicitation
            ? _CodexElicitationCard(
                request: entry.request!,
                onElicitation: widget.onElicitation,
              )
            : _CodexPendingCard(
                request: entry.request!,
                onReject: widget.onReject,
              ),
    };
    final anchorKey = cached?.anchorKey ?? GlobalKey();
    final entryWidget = Center(
      key: ValueKey<String>('$_entryKeyPrefix${entry.key}'),
      child: ConstrainedBox(
        key: anchorKey,
        constraints: const BoxConstraints(
          maxWidth: AleraTokens.codexConversationMaxWidth,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space16),
          child: SizedBox(width: .infinity, child: child),
        ),
      ),
    );
    _entryWidgets[entry.key] = (
      source: entry.source,
      widget: entryWidget,
      anchorKey: anchorKey,
    );
    while (_entryWidgets.length > _entryWidgetCacheLimit) {
      final evictionKey = _entryWidgets.keys.firstWhere(
        (key) => key != _pinnedEntryKey,
        orElse: () => '',
      );
      if (evictionKey.isEmpty) break;
      _entryWidgets.remove(evictionKey);
    }
    return entryWidget;
  }

  Widget _buildTurnEntry(_CodexTurnProjection turn) => _CodexTurnSection(
    projection: turn,
    workspacePath: widget.workspacePath,
    workedExpanded: turn.working
        ? !_collapsedWorkingTurns.contains(turn.turnId)
        : !turn.collapsesSecondaryRows ||
              _expandedWorkedTurns.contains(turn.turnId),
    onToggleWorked: () => _toggleWorkedTurn(turn.turnId, working: turn.working),
    expandedToolGroups: _expandedToolGroups,
    expandedToolActions: _expandedToolActions,
    onToggleToolGroup: (groupId) => _toggleToolGroup(turn.turnId, groupId),
    onToggleToolAction: (actionId) => _toggleToolAction(turn.turnId, actionId),
    onOpenAttachment: widget.onOpenAttachment,
  );

  int? _findEntryIndex(Key key) {
    if (key is! ValueKey<String> || !key.value.startsWith(_entryKeyPrefix)) {
      return null;
    }
    return _projection.entries.indexOfKey(
      key.value.substring(_entryKeyPrefix.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    if (snapshot.timelineCells.isEmpty &&
        snapshot.pendingRequests.isEmpty &&
        !widget.showRawLogs) {
      return Center(
        child: Column(
          mainAxisSize: .min,
          children: <Widget>[
            Text(
              widget.title.trim().isEmpty ? 'New Session' : widget.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AleraTokens.space8),
            Text(
              widget.workspacePath,
              style: AleraTokens.monoStyle.copyWith(
                color: AleraTokens.foregroundFaint,
              ),
            ),
            const SizedBox(height: AleraTokens.space16),
            const Text(
              'Start the conversation by sending a message',
              style: TextStyle(color: AleraTokens.foregroundFaint),
            ),
          ],
        ),
      );
    }
    return _CodexPlanViewScope(
      onMaximize: _maximizePlan,
      flyingPlanId: _flyingPlan?.id,
      latestPlanId: _projection.latestPlanId,
      overflowingPreviewIds: _overflowingPlanPreviewIds,
      onPreviewOverflowChanged: _handlePlanPreviewOverflow,
      child: Stack(
        key: _timelineViewportKey,
        clipBehavior: .hardEdge,
        children: <Widget>[
          SelectionArea(
            key: _timelineSelectionAreaKey,
            onSelectionChanged: (selection) =>
                _timelineHasSelection = selection?.plainText.isNotEmpty == true,
            child: CustomScrollView(
              key: const ValueKey<String>('codex-timeline-scroll-view'),
              controller: widget.timeline,
              slivers: <Widget>[
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AleraTokens.space24,
                  ),
                  sliver: SliverList.builder(
                    itemCount: _projection.entries.length,
                    itemBuilder: _buildEntry,
                    findChildIndexCallback: _findEntryIndex,
                  ),
                ),
              ],
            ),
          ),
          if (_showScrollToBottom && _flyingPlan == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: AleraTokens.space12,
              child: Center(
                child: IconButton(
                  key: const ValueKey<String>('scroll-to-bottom-button'),
                  tooltip: 'Scroll To Bottom',
                  onPressed: _scrollToBottom,
                  mouseCursor: SystemMouseCursors.click,
                  constraints: const BoxConstraints(
                    minWidth: AleraTokens.space32,
                    minHeight: AleraTokens.space32,
                  ),
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    backgroundColor: AleraTokens.bg,
                    foregroundColor: AleraTokens.foreground,
                    side: const BorderSide(
                      color: AleraTokens.border,
                      width: AleraTokens.dividerExtent,
                    ),
                    shape: const CircleBorder(),
                  ),
                  icon: const Icon(
                    Icons.arrow_downward,
                    size: AleraTokens.iconLg,
                  ),
                ),
              ),
            ),
          if (_flyingPlan case final CodexTimelineCell plan
              when _planSourceRect != null)
            _CodexPlanFlight(
              plan: plan,
              animation: _planFlight,
              selectionAreaKey: _planSelectionAreaKey,
              sourceRect: _planSourceRect!,
              currentSourceRect: _currentPlanSourceRect,
              onRestore: _restorePlan,
            ),
        ],
      ),
    );
  }
}
