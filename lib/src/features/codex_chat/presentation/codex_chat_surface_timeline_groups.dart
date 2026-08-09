part of 'codex_chat_surface.dart';

class _CodexTimeline extends StatefulWidget {
  const _CodexTimeline({
    super.key,
    required this.snapshot,
    required this.workspacePath,
    required this.title,
    required this.showRawLogs,
    required this.timeline,
    required this.loadingEarlier,
    required this.planDecisionRevision,
    required this.onApproval,
    required this.onElicitation,
    required this.onReject,
    required this.onOpenAttachment,
  });

  final CodexChatSnapshot snapshot;
  final String workspacePath;
  final String title;
  final bool showRawLogs;
  final ScrollController timeline;
  final bool loadingEarlier;
  final ValueNotifier<int> planDecisionRevision;
  final Future<void> Function(
    CodexPendingRequest request, {
    required Object decision,
  })
  onApproval;
  final Future<void> Function(
    CodexPendingRequest request, {
    required String action,
    Map<String, Object?> content,
  })
  onElicitation;
  final Future<void> Function(CodexPendingRequest request) onReject;
  final Future<void> Function(String path, {required bool isImage})
  onOpenAttachment;

  @override
  State<_CodexTimeline> createState() => _CodexTimelineState();
}

class _CodexTimelineState extends State<_CodexTimeline>
    with SingleTickerProviderStateMixin {
  static const int _entryWidgetCacheLimit = 128;

  final Set<String> _expandedWorkedTurns = <String>{};
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
  late final AnimationController _planFlight;
  late _CodexTimelineProjection _projection;
  List<CodexTimelineCell>? _frozenHistoryLiveCells;
  CodexTimelineCell? _flyingPlan;
  BuildContext? _planSourceContext;
  Rect? _planSourceRect;
  double? _planTimelineOffset;
  bool _showScrollToBottom = false;
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
    final newContent =
        oldWidget.snapshot.timelineCells.length !=
            widget.snapshot.timelineCells.length ||
        oldWidget.snapshot.pendingRequests.length !=
            widget.snapshot.pendingRequests.length;
    if (newContent && !_showScrollToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
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

  void _scrollToBottom() {
    if (!widget.timeline.hasClients) return;
    widget.timeline.animateTo(
      widget.timeline.position.maxScrollExtent,
      duration: AleraTokens.durationMid,
      curve: Curves.easeOut,
    );
  }

  void _restorePlan() {
    if (_flyingPlan == null || !mounted) return;
    unawaited(_planFlight.reverse());
  }

  void _toggleWorkedTurn(String turnId) {
    setState(() {
      _entryWidgets.remove('turn-$turnId');
      if (!_expandedWorkedTurns.add(turnId)) {
        _expandedWorkedTurns.remove(turnId);
      }
    });
  }

  void _maximizePlan(CodexTimelineCell cell, BuildContext sourceContext) {
    final viewport =
        _timelineViewportKey.currentContext?.findRenderObject() as RenderBox?;
    final source = sourceContext.findRenderObject() as RenderBox?;
    if (viewport == null || source == null || !viewport.hasSize) return;
    final sourceOrigin = source.localToGlobal(Offset.zero, ancestor: viewport);
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
    return source.localToGlobal(Offset.zero, ancestor: viewport) & source.size;
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
      _CodexTimelineEntryKind.turn => _CodexTurnSection(
        projection: entry.turn!,
        workspacePath: widget.workspacePath,
        workedExpanded: _expandedWorkedTurns.contains(entry.turn!.turnId),
        onToggleWorked: () => _toggleWorkedTurn(entry.turn!.turnId),
        onOpenAttachment: widget.onOpenAttachment,
      ),
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
      child: ConstrainedBox(
        key: anchorKey,
        constraints: const BoxConstraints(
          maxWidth: AleraTokens.codexConversationMaxWidth,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space16),
          child: SizedBox(width: double.infinity, child: child),
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

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    if (snapshot.timelineCells.isEmpty &&
        snapshot.pendingRequests.isEmpty &&
        !widget.showRawLogs) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
      child: Stack(
        key: _timelineViewportKey,
        clipBehavior: Clip.hardEdge,
        children: <Widget>[
          SelectionArea(
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
              sourceRect: _planSourceRect!,
              currentSourceRect: _currentPlanSourceRect,
              onRestore: _restorePlan,
            ),
        ],
      ),
    );
  }
}
