part of 'codex_chat_surface.dart';

class _CodexTimeline extends StatefulWidget {
  const _CodexTimeline({
    required this.snapshot,
    required this.workspacePath,
    required this.title,
    required this.planMode,
    required this.showRawLogs,
    required this.timeline,
    required this.onApproval,
    required this.onQuestion,
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
    return Stack(
      children: <Widget>[
        SelectionArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AleraTokens.codexConversationMaxWidth,
              ),
              child: ListView(
                controller: widget.timeline,
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space16,
                  vertical: AleraTokens.space24,
                ),
                children: <Widget>[
                  ..._buildTimeline(snapshot.timelineCells),
                  if (widget.showRawLogs)
                    for (final event in snapshot.events)
                      _CodexRawEvent(event: event),
                  for (final request in snapshot.pendingRequests)
                    if (request.isApproval)
                      _CodexApprovalCard(
                        request: request,
                        onApproval: widget.onApproval,
                      )
                    else if (request.isQuestion)
                      _CodexQuestionCard(
                        request: request,
                        onQuestion: widget.onQuestion,
                      )
                    else if (request.isElicitation)
                      _CodexElicitationCard(
                        request: request,
                        onElicitation: widget.onElicitation,
                      )
                    else
                      _CodexPendingCard(
                        request: request,
                        onReject: widget.onReject,
                      ),
                  if (widget.planMode && snapshot.shouldShowImplementPlan)
                    _CodexPlanPrompt(
                      onImplement: widget.onImplementPlan,
                      onDecline: widget.onDeclinePlan,
                      onRefine: widget.onRefinePlan,
                    ),
                ],
              ),
            ),
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

  List<Widget> _buildTimeline(List<CodexTimelineCell> cells) {
    final turnCells = <String, List<CodexTimelineCell>>{};
    final emittedTurns = <String>{};
    final result = <Widget>[];
    for (final cell in cells) {
      final turnId = cell.turnId;
      if (turnId == null || turnId.isEmpty) {
        if (cell.kind != CodexTimelineKind.turnSeparator) {
          result.add(
            _CodexCellView(cell: cell, workspacePath: widget.workspacePath),
          );
        }
        continue;
      }
      turnCells.putIfAbsent(turnId, () => <CodexTimelineCell>[]).add(cell);
      if (emittedTurns.add(turnId)) {
        result.add(
          _CodexTurnSection(
            key: ValueKey<String>('turn-$turnId'),
            cells: turnCells[turnId]!,
            workspacePath: widget.workspacePath,
            workedExpanded: _expandedWorkedTurns.contains(turnId),
            onToggleWorked: () => setState(() {
              if (!_expandedWorkedTurns.add(turnId)) {
                _expandedWorkedTurns.remove(turnId);
              }
            }),
          ),
        );
      }
    }
    // A streaming snapshot can add cells after the keyed section was built.
    // Rebuild sections from the complete map so no delta is lost.
    return <Widget>[
      for (final item in result)
        if (item is _CodexTurnSection)
          _CodexTurnSection(
            key: item.key,
            cells: turnCells[item.turnId] ?? item.cells,
            workspacePath: item.workspacePath,
            workedExpanded: item.workedExpanded,
            onToggleWorked: item.onToggleWorked,
          )
        else
          item,
    ];
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
