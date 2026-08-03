part of 'codex_chat_surface.dart';

class _CodexTimeline extends StatefulWidget {
  const _CodexTimeline({
    required this.snapshot,
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
  final bool showRawLogs;
  final ScrollController timeline;
  final Future<void> Function(
    CodexPendingRequest request, {
    required bool accepted,
    bool forSession,
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

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    if (snapshot.timelineCells.isEmpty &&
        snapshot.pendingRequests.isEmpty &&
        !widget.showRawLogs) {
      return const Center(child: Text('Ask Codex to work on this workspace.'));
    }
    return SelectionArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AleraTokens.conversationMaxWidth,
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
              if (snapshot.shouldShowImplementPlan)
                _CodexPlanPrompt(
                  onImplement: widget.onImplementPlan,
                  onDecline: widget.onDeclinePlan,
                  onRefine: widget.onRefinePlan,
                ),
            ],
          ),
        ),
      ),
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
          result.add(_CodexCellView(cell: cell));
        }
        continue;
      }
      turnCells.putIfAbsent(turnId, () => <CodexTimelineCell>[]).add(cell);
      if (emittedTurns.add(turnId)) {
        result.add(
          _CodexTurnSection(
            key: ValueKey<String>('turn-$turnId'),
            cells: turnCells[turnId]!,
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
    required this.workedExpanded,
    required this.onToggleWorked,
  });

  final List<CodexTimelineCell> cells;
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
      for (final cell in users) _CodexCellView(cell: cell),
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
          rows.map((row) => _CodexSecondaryRow(row: row)).toList(),
        );
      }
    } else {
      children.addAll(rows.map((row) => _CodexSecondaryRow(row: row)));
    }
    children.addAll(assistants.map((cell) => _CodexCellView(cell: cell)));
    children.addAll(outside.map((cell) => _CodexCellView(cell: cell)));
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
  const _CodexSecondaryRow({required this.row});

  final List<CodexTimelineCell> row;

  @override
  Widget build(BuildContext context) {
    if (row.length > 1) {
      return _CodexExploringCluster(cells: row);
    }
    return _CodexCellView(cell: row.single);
  }
}
