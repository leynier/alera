part of 'codex_chat_surface.dart';

class _CodexTimeline extends StatefulWidget {
  const _CodexTimeline({
    required this.snapshot,
    required this.workspacePath,
    required this.title,
    required this.planMode,
    required this.showRawLogs,
    required this.timeline,
    required this.historyNextCursor,
    required this.onLoadHistory,
    required this.onApproval,
    required this.onQuestion,
    required this.onQuestionInteraction,
    required this.onElicitation,
    required this.onReject,
    required this.onImplementPlan,
    required this.onDeclinePlan,
    required this.onRefinePlan,
  });

  final CodexChatSnapshot snapshot;
  final String workspacePath;
  final String title;
  final bool planMode;
  final bool showRawLogs;
  final ScrollController timeline;
  final String? historyNextCursor;
  final Future<void> Function({String? cursor}) onLoadHistory;
  final Future<void> Function(
    CodexPendingRequest request, {
    required Object decision,
  })
  onApproval;
  final Future<void> Function(
    CodexPendingRequest request,
    Map<String, List<String>> answers,
  )
  onQuestion;
  final Future<void> Function(CodexPendingRequest request)
  onQuestionInteraction;
  final Future<void> Function(
    CodexPendingRequest request, {
    required String action,
    Map<String, Object?> content,
  })
  onElicitation;
  final Future<void> Function(CodexPendingRequest request) onReject;
  final Future<void> Function() onImplementPlan;
  final Future<void> Function() onDeclinePlan;
  final Future<void> Function(String refinement) onRefinePlan;

  @override
  State<_CodexTimeline> createState() => _CodexTimelineState();
}

class _CodexTimelineState extends State<_CodexTimeline> {
  final Set<String> _expandedWorkedTurns = <String>{};
  List<CodexTimelineCell>? _cachedHistoryCells;
  List<_CodexTimelineSection> _cachedHistorySections =
      const <_CodexTimelineSection>[];
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    widget.timeline.addListener(_handleScroll);
  }

  @override
  void didUpdateWidget(covariant _CodexTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timeline != widget.timeline) {
      oldWidget.timeline.removeListener(_handleScroll);
      widget.timeline.addListener(_handleScroll);
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

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    if (snapshot.timelineCells.isEmpty &&
        snapshot.pendingRequests.isEmpty &&
        widget.historyNextCursor == null &&
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
    final sections = _timelineSections(snapshot.timelineCells);
    final hasHistoryAction = widget.historyNextCursor != null;
    final rawEventCount = widget.showRawLogs ? snapshot.events.length : 0;
    final showPlanPrompt = widget.planMode && snapshot.shouldShowImplementPlan;
    final itemCount =
        (hasHistoryAction ? 1 : 0) +
        sections.length +
        rawEventCount +
        snapshot.pendingRequests.length +
        (showPlanPrompt ? 1 : 0);
    return Stack(
      children: <Widget>[
        SelectionArea(
          child: CustomScrollView(
            controller: widget.timeline,
            slivers: <Widget>[
              SliverPadding(
                padding: const EdgeInsets.symmetric(
                  vertical: AleraTokens.space24,
                ),
                sliver: SliverList.builder(
                  itemCount: itemCount,
                  itemBuilder: (context, index) => Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AleraTokens.codexConversationMaxWidth,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AleraTokens.space16,
                        ),
                        child: _buildTimelineItem(
                          index: index,
                          sections: sections,
                          snapshot: snapshot,
                          hasHistoryAction: hasHistoryAction,
                          rawEventCount: rawEventCount,
                          showPlanPrompt: showPlanPrompt,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_showScrollToBottom)
          Positioned(
            right: AleraTokens.space16,
            bottom: AleraTokens.space12,
            child: AleraIconButton(
              tooltip: 'Scroll To Bottom',
              icon: AleraIcons.arrowDown,
              onPressed: _scrollToBottom,
            ),
          ),
      ],
    );
  }

  Widget _buildTimelineItem({
    required int index,
    required _CodexTimelineSections sections,
    required CodexChatSnapshot snapshot,
    required bool hasHistoryAction,
    required int rawEventCount,
    required bool showPlanPrompt,
  }) {
    var itemIndex = index;
    if (hasHistoryAction) {
      if (itemIndex == 0) {
        final cursor = widget.historyNextCursor!;
        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => unawaited(widget.onLoadHistory(cursor: cursor)),
            child: const Text('Load Earlier Messages'),
          ),
        );
      }
      itemIndex -= 1;
    }
    if (itemIndex < sections.length) {
      return _buildTimelineSection(sections[itemIndex]);
    }
    itemIndex -= sections.length;
    if (itemIndex < rawEventCount) {
      return _CodexRawEvent(event: snapshot.events[itemIndex]);
    }
    itemIndex -= rawEventCount;
    if (itemIndex < snapshot.pendingRequests.length) {
      return _buildPendingRequest(snapshot.pendingRequests[itemIndex]);
    }
    assert(showPlanPrompt && itemIndex == snapshot.pendingRequests.length);
    return _CodexPlanPrompt(
      onImplement: widget.onImplementPlan,
      onDecline: widget.onDeclinePlan,
      onRefine: widget.onRefinePlan,
    );
  }

  Widget _buildTimelineSection(_CodexTimelineSection section) {
    final cell = section.cell;
    if (cell != null) {
      return _CodexCellView(cell: cell, workspacePath: widget.workspacePath);
    }
    final turnId = section.turnId!;
    return _CodexTurnSection(
      key: ValueKey<String>('turn-$turnId'),
      cells: section.cells,
      workspacePath: widget.workspacePath,
      workedExpanded: _expandedWorkedTurns.contains(turnId),
      onToggleWorked: () => setState(() {
        if (!_expandedWorkedTurns.add(turnId)) {
          _expandedWorkedTurns.remove(turnId);
        }
      }),
    );
  }

  Widget _buildPendingRequest(CodexPendingRequest request) {
    if (request.isApproval) {
      return _CodexApprovalCard(
        request: request,
        onApproval: widget.onApproval,
      );
    }
    if (request.isQuestion) {
      return _CodexQuestionCard(
        key: ValueKey<Object>(request.id),
        request: request,
        onQuestion: widget.onQuestion,
        onInteraction: widget.onQuestionInteraction,
      );
    }
    if (request.isElicitation) {
      return _CodexElicitationCard(
        request: request,
        onElicitation: widget.onElicitation,
      );
    }
    return _CodexPendingCard(request: request, onReject: widget.onReject);
  }

  _CodexTimelineSections _timelineSections(List<CodexTimelineCell> cells) {
    if (cells case final CodexTimelineCells segmented) {
      if (!identical(_cachedHistoryCells, segmented.history)) {
        _cachedHistoryCells = segmented.history;
        _cachedHistorySections = _groupTimeline(segmented.history);
      }
      return _CodexTimelineSections(
        history: _cachedHistorySections,
        live: _groupTimeline(segmented.live),
      );
    }
    return _CodexTimelineSections(
      history: const <_CodexTimelineSection>[],
      live: _groupTimeline(cells),
    );
  }

  List<_CodexTimelineSection> _groupTimeline(List<CodexTimelineCell> cells) {
    final turnCells = <String, List<CodexTimelineCell>>{};
    final emittedTurns = <String>{};
    final order = <({CodexTimelineCell? cell, String? turnId})>[];
    for (final cell in cells) {
      final turnId = cell.turnId;
      if (turnId == null || turnId.isEmpty) {
        if (cell.kind != CodexTimelineKind.turnSeparator) {
          order.add((cell: cell, turnId: null));
        }
        continue;
      }
      turnCells.putIfAbsent(turnId, () => <CodexTimelineCell>[]).add(cell);
      if (emittedTurns.add(turnId)) {
        order.add((cell: null, turnId: turnId));
      }
    }
    return <_CodexTimelineSection>[
      for (final item in order)
        if (item.cell case final cell?)
          _CodexTimelineSection.cell(cell)
        else
          _CodexTimelineSection.turn(
            item.turnId!,
            List<CodexTimelineCell>.unmodifiable(turnCells[item.turnId]!),
          ),
    ];
  }
}

final class _CodexTimelineSection {
  const _CodexTimelineSection.cell(this.cell)
    : turnId = null,
      cells = const <CodexTimelineCell>[];

  const _CodexTimelineSection.turn(this.turnId, this.cells) : cell = null;

  final CodexTimelineCell? cell;
  final String? turnId;
  final List<CodexTimelineCell> cells;
}

final class _CodexTimelineSections {
  _CodexTimelineSections({required this.history, required this.live})
    : _mergedBoundary = _mergeBoundary(history, live);

  final List<_CodexTimelineSection> history;
  final List<_CodexTimelineSection> live;
  final _CodexTimelineSection? _mergedBoundary;

  int get length =>
      history.length + live.length - (_mergedBoundary == null ? 0 : 1);

  _CodexTimelineSection operator [](int index) {
    RangeError.checkValidIndex(index, this);
    final mergedBoundary = _mergedBoundary;
    if (mergedBoundary == null) {
      return index < history.length
          ? history[index]
          : live[index - history.length];
    }
    final boundaryIndex = history.length - 1;
    if (index < boundaryIndex) return history[index];
    if (index == boundaryIndex) return mergedBoundary;
    return live[index - boundaryIndex];
  }

  static _CodexTimelineSection? _mergeBoundary(
    List<_CodexTimelineSection> history,
    List<_CodexTimelineSection> live,
  ) {
    if (history.isEmpty || live.isEmpty) return null;
    final before = history.last;
    final after = live.first;
    if (before.turnId == null || before.turnId != after.turnId) return null;
    return _CodexTimelineSection.turn(
      before.turnId,
      List<CodexTimelineCell>.unmodifiable(<CodexTimelineCell>[
        ...before.cells,
        ...after.cells,
      ]),
    );
  }
}

class _CodexTurnSection extends StatelessWidget {
  const _CodexTurnSection({
    super.key,
    required this.cells,
    required this.workspacePath,
    required this.workedExpanded,
    required this.onToggleWorked,
  });

  final List<CodexTimelineCell> cells;
  final String workspacePath;
  final bool workedExpanded;
  final VoidCallback onToggleWorked;

  String get turnId => cells.first.turnId ?? cells.first.id;

  @override
  Widget build(BuildContext context) {
    final users = <CodexTimelineCell>[];
    final assistants = <CodexTimelineCell>[];
    final secondary = <CodexTimelineCell>[];
    final outside = <CodexTimelineCell>[];
    for (final cell in cells) {
      switch (cell.kind) {
        case CodexTimelineKind.turnSeparator:
          break;
        case CodexTimelineKind.userMessage:
          if (cell.metadata[CodexTimelineMetadata.isSteering] == true) {
            assistants.add(cell);
          } else {
            users.add(cell);
          }
        case CodexTimelineKind.assistantMessage || CodexTimelineKind.plan:
          assistants.add(cell);
        case CodexTimelineKind.progressText:
          if (cell.metadata[CodexTimelineMetadata.uiPlacement] ==
              CodexTimelineMetadata.outsideWorked) {
            outside.add(cell);
          } else if ((cell.markdownText ?? '').trim().isNotEmpty) {
            secondary.add(cell);
          }
        case CodexTimelineKind.reasoning ||
            CodexTimelineKind.toolCall ||
            CodexTimelineKind.command ||
            CodexTimelineKind.diff ||
            CodexTimelineKind.subAgent ||
            CodexTimelineKind.questionAnswer:
          secondary.add(cell);
        case CodexTimelineKind.systemNotice:
          secondary.add(cell);
      }
    }
    final rows = _secondaryRows(secondary);
    final children = <Widget>[
      for (final cell in users)
        _CodexCellView(cell: cell, workspacePath: workspacePath),
    ];
    if (rows.length > 1) {
      children.add(
        _WorkedForDivider(
          expanded: workedExpanded,
          label: _workedFor(cells),
          onTap: onToggleWorked,
        ),
      );
      if (workedExpanded) {
        children.addAll(
          rows
              .map(
                (row) =>
                    _CodexSecondaryRow(row: row, workspacePath: workspacePath),
              )
              .toList(),
        );
      }
    } else {
      children.addAll(
        rows.map(
          (row) => _CodexSecondaryRow(row: row, workspacePath: workspacePath),
        ),
      );
    }
    children.addAll(
      assistants.map(
        (cell) => _CodexCellView(cell: cell, workspacePath: workspacePath),
      ),
    );
    children.addAll(
      outside.map(
        (cell) => _CodexCellView(cell: cell, workspacePath: workspacePath),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _CodexSecondaryRow extends StatelessWidget {
  const _CodexSecondaryRow({required this.row, required this.workspacePath});

  final List<CodexTimelineCell> row;
  final String workspacePath;

  @override
  Widget build(BuildContext context) {
    if (row.length > 1) {
      return _CodexExploringCluster(cells: row, workspacePath: workspacePath);
    }
    return _CodexCellView(cell: row.single, workspacePath: workspacePath);
  }
}
