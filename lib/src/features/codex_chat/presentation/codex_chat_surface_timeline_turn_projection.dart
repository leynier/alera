part of 'codex_chat_surface.dart';

class const _CodexTurnProjection({
  required final String turnId,
  required final List<CodexTimelineCell> users,
  required final List<CodexTimelineCell> assistants,
  required final List<_CodexSecondaryRowProjection> secondaryRows,
  required final List<CodexTimelineCell> outside,
  required final bool working,
  required final String workedLabel,
  required final DateTime? startedAt,
  required final List<CodexTimelineCell> sourceCells,
}) {
  factory reuseOrCreate(
    _CodexTurnProjection? previous,
    List<CodexTimelineCell> cells, {
    required bool working,
  }) {
    if (previous != null &&
        previous.working == working &&
        _sameCodexCellIdentities(previous.sourceCells, cells)) {
      return previous;
    }
    return _CodexTurnProjection.fromCells(cells, working: working);
  }

  factory fromCells(List<CodexTimelineCell> cells, {required bool working}) {
    final users = <CodexTimelineCell>[];
    final assistants = <CodexTimelineCell>[];
    final secondary = <CodexTimelineCell>[];
    final outside = <CodexTimelineCell>[];
    for (final cell in cells) {
      switch (cell.kind) {
        case CodexTimelineKind.turnSeparator || CodexTimelineKind.reasoning:
          break;
        case CodexTimelineKind.userMessage:
          if (cell.metadata[CodexTimelineMetadata.isSteering] == true) {
            assistants.add(cell);
          } else {
            users.add(cell);
          }
        case CodexTimelineKind.assistantMessage:
          assistants.add(cell);
        case CodexTimelineKind.plan:
          if (cell.metadata['plan'] is! List) assistants.add(cell);
        case CodexTimelineKind.progressText:
          if (cell.metadata[CodexTimelineMetadata.uiPlacement] ==
              CodexTimelineMetadata.outsideWorked) {
            outside.add(cell);
          } else if ((cell.markdownText ?? '').trim().isNotEmpty) {
            secondary.add(cell);
          }
        case CodexTimelineKind.toolCall ||
            CodexTimelineKind.command ||
            CodexTimelineKind.subAgent ||
            CodexTimelineKind.questionAnswer ||
            CodexTimelineKind.systemNotice:
          secondary.add(cell);
        case CodexTimelineKind.diff:
          if (cell.metadata['supersededByStructuredFileChanges'] == true) {
            break;
          }
          final details = cell.detailsText ?? cell.markdownText ?? '';
          if (cell.status != CodexTimelineStatus.completed ||
              cell.isStreaming ||
              _hasCodexDiffDetails(details) ||
              _codexChangeCount(cell, _codexChanges(cell.metadata['changes'])) >
                  0) {
            secondary.add(cell);
          }
      }
    }
    final grouped = _secondaryRows(secondary);
    final latestActivity = _latestCodexTurnActivity(cells);
    final waitingAfterWorked =
        working &&
        grouped.isNotEmpty &&
        _isWorkedActionCell(grouped.last.last) &&
        !grouped.last.any((cell) => cell.isStreaming) &&
        latestActivity?.id == grouped.last.last.id;
    final rows = <_CodexSecondaryRowProjection>[
      for (var index = 0; index < grouped.length; index += 1)
        _CodexSecondaryRowProjection.fromCells(
          grouped[index],
          waiting: waitingAfterWorked && index == grouped.length - 1,
        ),
    ];
    return _CodexTurnProjection(
      turnId: cells.first.turnId ?? cells.first.id,
      users: List<CodexTimelineCell>.unmodifiableOf(users),
      assistants: List<CodexTimelineCell>.unmodifiableOf(assistants),
      secondaryRows: List<_CodexSecondaryRowProjection>.unmodifiableOf(rows),
      outside: List<CodexTimelineCell>.unmodifiableOf(outside),
      working: working,
      workedLabel: _workedFor(cells),
      startedAt: _codexTurnStartedAt(cells),
      sourceCells: List<CodexTimelineCell>.unmodifiableOf(cells),
    );
  }

  bool get hasSecondaryRows => secondaryRows.isNotEmpty;
  bool get collapsesSecondaryRows =>
      secondaryRows.fold<int>(
        0,
        (count, row) => count + (row.actions.isEmpty ? 1 : row.actions.length),
      ) >
      1;
  bool get canToggleWorked =>
      working ? hasSecondaryRows : collapsesSecondaryRows;
}

class _CodexSecondaryRowProjection {
  const new cell(this.cell)
    : actions = const <_CodexWorkedAction>[],
      summary = null,
      summaryIcon = null,
      streaming = false,
      waiting = false;

  new actions(
    this.actions, {
    required this.summary,
    required this.summaryIcon,
    required this.streaming,
    required this.waiting,
  }) : cell = null;

  factory fromCells(List<CodexTimelineCell> cells, {required bool waiting}) {
    if (!_isWorkedActionCell(cells.first)) {
      return _CodexSecondaryRowProjection.cell(cells.single);
    }
    final actions = cells.map(_codexWorkedAction).toList(growable: false);
    return _CodexSecondaryRowProjection.actions(
      List<_CodexWorkedAction>.unmodifiableOf(actions),
      summary: _codexWorkedSummary(actions),
      summaryIcon: _codexWorkedSummaryIcon(actions),
      streaming: waiting || cells.any((cell) => cell.isStreaming),
      waiting: waiting,
    );
  }

  final CodexTimelineCell? cell;
  final List<_CodexWorkedAction> actions;
  final String? summary;
  final IconData? summaryIcon;
  final bool streaming;
  final bool waiting;

  bool get isWorked => actions.isNotEmpty;
  bool get isGroup => actions.length > 1 || waiting;
  String get key => cell?.id ?? actions.first.cell.id;
}

bool _sameCodexCellIdentities(
  List<CodexTimelineCell> previous,
  List<CodexTimelineCell> next,
) {
  if (previous.length != next.length) return false;
  for (var index = 0; index < previous.length; index += 1) {
    if (!identical(previous[index], next[index])) return false;
  }
  return true;
}
