import 'dart:convert';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';
import 'package:alera/src/features/session/domain/codex_model_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

class SessionWorkspaceView extends StatefulWidget {
  const SessionWorkspaceView({
    super.key,
    required this.state,
    required this.onSendInput,
    required this.onInterruptTurn,
    required this.isTurnRunning,
    required this.isInterrupting,
    required this.onModelChanged,
    required this.activeReasoningEffort,
    required this.supportedReasoningEfforts,
    required this.onReasoningEffortChanged,
    required this.isMarkdownEnabled,
    required this.onMarkdownModeChanged,
    required this.rawLogExpanded,
  });

  final SessionState state;
  final ValueChanged<String> onSendInput;
  final VoidCallback onInterruptTurn;
  final bool isTurnRunning;
  final bool isInterrupting;
  final ValueChanged<String> onModelChanged;
  final String activeReasoningEffort;
  final List<String> supportedReasoningEfforts;
  final ValueChanged<String> onReasoningEffortChanged;
  final bool isMarkdownEnabled;
  final ValueChanged<bool> onMarkdownModeChanged;
  final bool rawLogExpanded;

  @override
  State<SessionWorkspaceView> createState() => _SessionWorkspaceViewState();
}

class _SessionWorkspaceViewState extends State<SessionWorkspaceView> {
  static const double _bottomTolerancePx = 1;

  final _inputController = TextEditingController();
  final Set<String> _expandedWorkedTurns = <String>{};
  final ScrollController _timelineScrollController = ScrollController();
  bool _showScrollToBottom = false;
  bool _pendingScrollAfterSend = false;

  @override
  void initState() {
    super.initState();
    _timelineScrollController.addListener(_handleTimelineScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollToBottomVisibility();
    });
  }

  @override
  void didUpdateWidget(covariant SessionWorkspaceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.activeSessionId != widget.state.activeSessionId) {
      _expandedWorkedTurns.clear();
    }

    final timelineChanged = !identical(
      oldWidget.state.timelineCells,
      widget.state.timelineCells,
    );
    final hasNonUserTimelineChanges =
        timelineChanged &&
        _hasNonUserTimelineChanges(
          oldWidget.state.timelineCells,
          widget.state.timelineCells,
        );
    final shouldAutoScrollForAi =
        hasNonUserTimelineChanges &&
        _isAtBottom(tolerancePx: _bottomTolerancePx);
    final shouldAutoScrollForSend = _pendingScrollAfterSend && timelineChanged;

    if (shouldAutoScrollForAi || shouldAutoScrollForSend) {
      _scheduleScrollToBottom(animated: shouldAutoScrollForSend);
      if (shouldAutoScrollForSend) {
        _pendingScrollAfterSend = false;
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScrollToBottomVisibility();
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _timelineScrollController.removeListener(_handleTimelineScroll);
    _timelineScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasWorkspace =
        (widget.state.selectedWorkspacePath != null &&
            widget.state.selectedWorkspacePath!.isNotEmpty) ||
        widget.state.activeSession != null;
    return Column(
      children: <Widget>[
        Expanded(
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: _ChatTimelineList(
                  state: widget.state,
                  expandedWorkedTurns: _expandedWorkedTurns,
                  onToggleWorkedTurn: _toggleWorkedTurn,
                  controller: _timelineScrollController,
                  markdownEnabled: widget.isMarkdownEnabled,
                  onMarkdownModeChanged: widget.onMarkdownModeChanged,
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AleraTokens.space12),
                  child: IgnorePointer(
                    ignoring: !_showScrollToBottom,
                    child: AnimatedOpacity(
                      duration: AleraTokens.durationFast,
                      opacity: _showScrollToBottom ? 1 : 0,
                      child: IconButton(
                        key: const ValueKey<String>('scroll-to-bottom-button'),
                        onPressed: _showScrollToBottom
                            ? () => _scheduleScrollToBottom(animated: true)
                            : null,
                        mouseCursor: SystemMouseCursors.click,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(
                          backgroundColor: AleraTokens.bg,
                          foregroundColor: AleraTokens.foreground,
                          side: const BorderSide(
                            color: AleraTokens.border,
                            width: 1,
                          ),
                          shape: const CircleBorder(),
                        ),
                        icon: const Icon(Icons.arrow_downward, size: 16),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        _Composer(
          controller: _inputController,
          textFieldEnabled: hasWorkspace,
          canSend:
              hasWorkspace &&
              !widget.state.isBusy &&
              !widget.isTurnRunning &&
              !widget.isInterrupting,
          canStop:
              widget.state.activeSession != null &&
              widget.isTurnRunning &&
              !widget.state.isBusy,
          canChangeModel: hasWorkspace,
          isBusy: widget.state.isBusy,
          isInterrupting: widget.isInterrupting,
          activeModelId: widget.state.activeModelId,
          availableModels: widget.state.availableModels,
          onModelChanged: widget.onModelChanged,
          activeReasoningEffort: widget.activeReasoningEffort,
          supportedReasoningEfforts: widget.supportedReasoningEfforts,
          onReasoningEffortChanged: widget.onReasoningEffortChanged,
          onSend: _sendInput,
          onInterrupt: widget.onInterruptTurn,
        ),
        _RawLog(state: widget.state, expanded: widget.rawLogExpanded),
      ],
    );
  }

  void _sendInput() {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      return;
    }
    _inputController.clear();
    _pendingScrollAfterSend = true;
    _scheduleScrollToBottom(animated: true);
    widget.onSendInput(text);
  }

  void _toggleWorkedTurn(String turnId) {
    setState(() {
      if (_expandedWorkedTurns.contains(turnId)) {
        _expandedWorkedTurns.remove(turnId);
      } else {
        _expandedWorkedTurns.add(turnId);
      }
    });
  }

  bool _hasNonUserTimelineChanges(
    List<TimelineCell> previous,
    List<TimelineCell> next,
  ) {
    final previousById = <String, TimelineCell>{
      for (final cell in previous) cell.id: cell,
    };

    for (final cell in next) {
      final old = previousById.remove(cell.id);
      if (old == null) {
        if (cell.kind != TimelineCellKind.userMessage) {
          return true;
        }
        continue;
      }
      if (_hasCellChanged(old, cell) &&
          cell.kind != TimelineCellKind.userMessage) {
        return true;
      }
    }

    for (final removed in previousById.values) {
      if (removed.kind != TimelineCellKind.userMessage) {
        return true;
      }
    }

    return false;
  }

  bool _hasCellChanged(TimelineCell previous, TimelineCell next) {
    return previous.status != next.status ||
        previous.updatedAt != next.updatedAt ||
        previous.isStreaming != next.isStreaming ||
        previous.isCollapsed != next.isCollapsed ||
        previous.title != next.title ||
        previous.subtitle != next.subtitle ||
        previous.markdownText != next.markdownText ||
        previous.detailsText != next.detailsText;
  }

  void _handleTimelineScroll() {
    _updateScrollToBottomVisibility();
  }

  bool _isAtBottom({required double tolerancePx}) {
    if (!_timelineScrollController.hasClients) {
      return true;
    }
    final position = _timelineScrollController.position;
    final distanceToBottom = (position.maxScrollExtent - position.pixels).clamp(
      0.0,
      double.infinity,
    );
    return distanceToBottom <= tolerancePx;
  }

  void _updateScrollToBottomVisibility() {
    if (!mounted) {
      return;
    }
    if (!_timelineScrollController.hasClients) {
      if (_showScrollToBottom) {
        setState(() => _showScrollToBottom = false);
      }
      return;
    }
    final shouldShow = !_isAtBottom(tolerancePx: _bottomTolerancePx);
    if (shouldShow == _showScrollToBottom) {
      return;
    }
    setState(() {
      _showScrollToBottom = shouldShow;
    });
  }

  void _scheduleScrollToBottom({bool animated = false}) {
    _scrollToBottomIfPossible(animated: animated);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottomIfPossible(animated: animated);
    });
  }

  bool _scrollToBottomIfPossible({required bool animated}) {
    if (!mounted || !_timelineScrollController.hasClients) {
      return false;
    }
    final target = _timelineScrollController.position.maxScrollExtent;
    if (animated) {
      _timelineScrollController
          .animateTo(
            target,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(_updateScrollToBottomVisibility);
      return true;
    }
    _timelineScrollController.jumpTo(target);
    _updateScrollToBottomVisibility();
    return true;
  }
}

class _ChatTimelineList extends StatelessWidget {
  const _ChatTimelineList({
    required this.state,
    required this.expandedWorkedTurns,
    required this.onToggleWorkedTurn,
    required this.controller,
    required this.markdownEnabled,
    required this.onMarkdownModeChanged,
  });

  final SessionState state;
  final Set<String> expandedWorkedTurns;
  final ValueChanged<String> onToggleWorkedTurn;
  final ScrollController controller;
  final bool markdownEnabled;
  final ValueChanged<bool> onMarkdownModeChanged;

  @override
  Widget build(BuildContext context) {
    if (state.timelineCells.isEmpty) {
      return _EmptyChatState(state: state);
    }

    final timelineWidgets = _buildTimelineWidgets();
    return SelectionArea(
      child: ListView(
        key: const ValueKey<String>('timeline-list'),
        controller: controller,
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space16,
          vertical: AleraTokens.space16,
        ),
        children: timelineWidgets,
      ),
    );
  }

  List<Widget> _buildTimelineWidgets() {
    final cells = state.timelineCells;
    final separatorsByTurn = <String, TimelineCell>{};
    final firstIndexByTurn = <String, int>{};

    for (var i = 0; i < cells.length; i++) {
      final cell = cells[i];
      final turnId = cell.turnId;
      if (turnId != null) {
        firstIndexByTurn.putIfAbsent(turnId, () => i);
        if (cell.kind == TimelineCellKind.turnSeparator) {
          separatorsByTurn[turnId] = cell;
        }
      }
    }

    final renderedCompletedTurns = <String>{};
    final widgets = <Widget>[];

    for (var i = 0; i < cells.length; i++) {
      final cell = cells[i];
      final turnId = cell.turnId;
      if (turnId == null) {
        if (cell.kind == TimelineCellKind.turnSeparator) {
          continue;
        }
        widgets.add(_timelineCellWithSpacing(cell));
        continue;
      }

      final separator = separatorsByTurn[turnId];
      final isCompletedTurn = separator != null;
      if (!isCompletedTurn) {
        if (cell.kind == TimelineCellKind.turnSeparator) {
          continue;
        }
        if (_isExploratoryToolCell(cell)) {
          final runLength = _exploratoryRunLength(cells, i);
          if (runLength >= 2) {
            final cluster = cells.sublist(i, i + runLength);
            widgets.add(
              Padding(
                padding: const EdgeInsets.only(bottom: AleraTokens.space8),
                child: _ExploringClusterCell(
                  key: ValueKey(
                    'cluster-open-${cluster.first.id}-${cluster.last.id}',
                  ),
                  cells: cluster,
                ),
              ),
            );
            i += runLength - 1;
            continue;
          }
        }
        widgets.add(_timelineCellWithSpacing(cell));
        continue;
      }

      final firstTurnIndex = firstIndexByTurn[turnId];
      if (firstTurnIndex != i || renderedCompletedTurns.contains(turnId)) {
        continue;
      }
      renderedCompletedTurns.add(turnId);

      final turnCells = cells
          .where(
            (candidate) =>
                candidate.turnId == turnId &&
                candidate.kind != TimelineCellKind.turnSeparator,
          )
          .toList(growable: false);
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AleraTokens.space8),
          child: _CompletedTurnSection(
            turnId: turnId,
            separator: separator,
            turnCells: turnCells,
            workedExpanded: expandedWorkedTurns.contains(turnId),
            onToggleWorked: () => onToggleWorkedTurn(turnId),
            markdownEnabled: markdownEnabled,
            onMarkdownModeChanged: onMarkdownModeChanged,
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _timelineCellWithSpacing(TimelineCell cell) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space8),
      child: _TimelineCellView(
        cell: cell,
        markdownEnabled: markdownEnabled,
        onMarkdownModeChanged: onMarkdownModeChanged,
      ),
    );
  }

  int _exploratoryRunLength(List<TimelineCell> cells, int startIndex) {
    final start = cells[startIndex];
    if (!_isExploratoryToolCell(start)) {
      return 0;
    }

    final turnId = start.turnId;
    var current = startIndex;
    while (current < cells.length) {
      final candidate = cells[current];
      if (candidate.kind == TimelineCellKind.turnSeparator) {
        break;
      }
      if (candidate.turnId != turnId) {
        break;
      }
      if (!_isExploratoryToolCell(candidate)) {
        break;
      }
      current += 1;
    }
    return current - startIndex;
  }
}

class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState({required this.state});

  final SessionState state;

  @override
  Widget build(BuildContext context) {
    final session = state.activeSession;
    final workspacePath = session?.workspacePath ?? state.selectedWorkspacePath;
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            session?.title ?? 'new session',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AleraTokens.space8),
          if (workspacePath != null && workspacePath.isNotEmpty)
            Text(
              workspacePath,
              style: AleraTokens.monoStyle.copyWith(
                color: AleraTokens.foregroundFaint,
              ),
            ),
          const SizedBox(height: AleraTokens.space16),
          const Text(
            'start the conversation by sending a message',
            style: TextStyle(color: AleraTokens.foregroundFaint),
          ),
        ],
      ),
    );
  }
}

class _TimelineCellView extends StatelessWidget {
  const _TimelineCellView({
    required this.cell,
    required this.markdownEnabled,
    required this.onMarkdownModeChanged,
  });

  final TimelineCell cell;
  final bool markdownEnabled;
  final ValueChanged<bool> onMarkdownModeChanged;

  @override
  Widget build(BuildContext context) {
    return switch (cell.kind) {
      TimelineCellKind.userMessage => _UserMessageCell(
        cell: cell,
        markdownEnabled: markdownEnabled,
        onMarkdownModeChanged: onMarkdownModeChanged,
      ),
      TimelineCellKind.assistantMessage => _AssistantMessageCell(
        cell: cell,
        markdownEnabled: markdownEnabled,
        onMarkdownModeChanged: onMarkdownModeChanged,
      ),
      TimelineCellKind.progressText => _ProgressTextRow(
        cell: cell,
        markdownEnabled: markdownEnabled,
      ),
      TimelineCellKind.reasoning => _ReasoningCell(
        key: ValueKey(cell.id),
        cell: cell,
        markdownEnabled: markdownEnabled,
      ),
      TimelineCellKind.toolCall => _ToolCallCell(
        key: ValueKey(cell.id),
        cell: cell,
      ),
      TimelineCellKind.turnSeparator => const SizedBox.shrink(),
      TimelineCellKind.systemNotice => _SystemNoticeCell(cell: cell),
    };
  }
}

class _SecondaryRenderRow {
  _SecondaryRenderRow.single(this.cell) : clusterCells = null;

  _SecondaryRenderRow.cluster(List<TimelineCell> cells)
    : cell = null,
      clusterCells = List<TimelineCell>.unmodifiable(cells);

  final TimelineCell? cell;
  final List<TimelineCell>? clusterCells;

  bool get isCluster => clusterCells != null;
}

List<_SecondaryRenderRow> _buildSecondaryRows(List<TimelineCell> cells) {
  final rows = <_SecondaryRenderRow>[];
  final renderable = cells
      .where(_isRenderableSecondaryCell)
      .toList(growable: false);
  var index = 0;
  while (index < renderable.length) {
    final cell = renderable[index];
    if (_isExploratoryToolCell(cell)) {
      var end = index + 1;
      while (end < renderable.length &&
          _isExploratoryToolCell(renderable[end])) {
        end += 1;
      }
      final sequence = renderable.sublist(index, end);
      if (sequence.length >= 2) {
        rows.add(_SecondaryRenderRow.cluster(sequence));
      } else {
        rows.add(_SecondaryRenderRow.single(cell));
      }
      index = end;
      continue;
    }
    rows.add(_SecondaryRenderRow.single(cell));
    index += 1;
  }
  return rows;
}

bool _isRenderableSecondaryCell(TimelineCell cell) {
  if (cell.kind != TimelineCellKind.progressText) {
    return true;
  }
  return (cell.markdownText ?? '').trim().isNotEmpty;
}

bool _isExploratoryToolCell(TimelineCell cell) {
  if (cell.kind != TimelineCellKind.toolCall) {
    return false;
  }

  final flag = cell.metadata['isExploratory'];
  if (flag is bool) {
    return flag;
  }
  if (flag is String) {
    final value = flag.toLowerCase().trim();
    if (value == 'true') {
      return true;
    }
    if (value == 'false') {
      return false;
    }
  }

  final bucket = cell.metadata['exploreBucket']?.toString().toLowerCase();
  if (bucket == 'file' || bucket == 'search') {
    return true;
  }

  final title = (cell.title ?? '').toLowerCase();
  return title.startsWith('read') ||
      title.startsWith('list') ||
      title.startsWith('search');
}

class _SecondaryRowView extends StatelessWidget {
  const _SecondaryRowView({
    required this.row,
    required this.markdownEnabled,
    required this.onMarkdownModeChanged,
  });

  final _SecondaryRenderRow row;
  final bool markdownEnabled;
  final ValueChanged<bool> onMarkdownModeChanged;

  @override
  Widget build(BuildContext context) {
    if (row.isCluster) {
      return _ExploringClusterCell(
        key: ValueKey(
          'cluster-${row.clusterCells!.first.id}-${row.clusterCells!.last.id}',
        ),
        cells: row.clusterCells!,
      );
    }
    return _TimelineCellView(
      cell: row.cell!,
      markdownEnabled: markdownEnabled,
      onMarkdownModeChanged: onMarkdownModeChanged,
    );
  }
}

class _CompletedTurnSection extends StatelessWidget {
  const _CompletedTurnSection({
    required this.turnId,
    required this.separator,
    required this.turnCells,
    required this.workedExpanded,
    required this.onToggleWorked,
    required this.markdownEnabled,
    required this.onMarkdownModeChanged,
  });

  final String turnId;
  final TimelineCell separator;
  final List<TimelineCell> turnCells;
  final bool workedExpanded;
  final VoidCallback onToggleWorked;
  final bool markdownEnabled;
  final ValueChanged<bool> onMarkdownModeChanged;

  @override
  Widget build(BuildContext context) {
    final users = <TimelineCell>[];
    final assistants = <TimelineCell>[];
    final secondary = <TimelineCell>[];
    final postTurnNotices = <TimelineCell>[];

    for (final cell in turnCells) {
      switch (cell.kind) {
        case TimelineCellKind.userMessage:
          users.add(cell);
        case TimelineCellKind.assistantMessage:
          assistants.add(cell);
        case TimelineCellKind.progressText:
          secondary.add(cell);
        case TimelineCellKind.reasoning || TimelineCellKind.toolCall:
          secondary.add(cell);
        case TimelineCellKind.systemNotice:
          final placement = (cell.metadata['uiPlacement'] ?? '')
              .toString()
              .toLowerCase()
              .trim();
          if (placement == 'outside_worked') {
            postTurnNotices.add(cell);
          } else {
            secondary.add(cell);
          }
        case TimelineCellKind.turnSeparator:
          break;
      }
    }

    final secondaryRows = _buildSecondaryRows(secondary);
    final shouldRenderWorked = secondaryRows.length > 1;
    final shouldRenderSingleSecondary = secondaryRows.length == 1;
    final workedLabel = shouldRenderWorked ? _workedForLabel(separator) : null;
    final effectiveWorkedExpanded = workedLabel == null ? true : workedExpanded;

    final children = <Widget>[
      for (final userCell in users)
        Padding(
          padding: const EdgeInsets.only(bottom: AleraTokens.space8),
          child: _TimelineCellView(
            cell: userCell,
            markdownEnabled: markdownEnabled,
            onMarkdownModeChanged: onMarkdownModeChanged,
          ),
        ),
    ];

    if (shouldRenderWorked && workedLabel != null) {
      children.add(
        _WorkedForDivider(
          label: workedLabel,
          expanded: effectiveWorkedExpanded,
          onTap: onToggleWorked,
        ),
      );
      if (effectiveWorkedExpanded) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: AleraTokens.space8),
            child: Column(
              children: <Widget>[
                for (final row in secondaryRows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AleraTokens.space6),
                    child: _SecondaryRowView(
                      row: row,
                      markdownEnabled: markdownEnabled,
                      onMarkdownModeChanged: onMarkdownModeChanged,
                    ),
                  ),
              ],
            ),
          ),
        );
      }
    }

    if (shouldRenderWorked && workedLabel == null) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AleraTokens.space8),
          child: Column(
            children: <Widget>[
              for (final row in secondaryRows)
                Padding(
                  padding: const EdgeInsets.only(bottom: AleraTokens.space6),
                  child: _SecondaryRowView(
                    row: row,
                    markdownEnabled: markdownEnabled,
                    onMarkdownModeChanged: onMarkdownModeChanged,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (shouldRenderSingleSecondary) {
      children.add(
        Padding(
          padding: const EdgeInsets.only(bottom: AleraTokens.space8),
          child: _SecondaryRowView(
            row: secondaryRows.first,
            markdownEnabled: markdownEnabled,
            onMarkdownModeChanged: onMarkdownModeChanged,
          ),
        ),
      );
    }

    children.addAll(
      assistants.map(
        (assistantCell) => Padding(
          padding: const EdgeInsets.only(bottom: AleraTokens.space8),
          child: _TimelineCellView(
            cell: assistantCell,
            markdownEnabled: markdownEnabled,
            onMarkdownModeChanged: onMarkdownModeChanged,
          ),
        ),
      ),
    );
    children.addAll(
      postTurnNotices.map(
        (noticeCell) => Padding(
          padding: const EdgeInsets.only(bottom: AleraTokens.space8),
          child: _TimelineCellView(
            cell: noticeCell,
            markdownEnabled: markdownEnabled,
            onMarkdownModeChanged: onMarkdownModeChanged,
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _ExploringClusterCell extends StatefulWidget {
  const _ExploringClusterCell({super.key, required this.cells});

  final List<TimelineCell> cells;

  @override
  State<_ExploringClusterCell> createState() => _ExploringClusterCellState();
}

class _ExploringClusterCellState extends State<_ExploringClusterCell> {
  late bool _collapsed;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _collapsed = true;
  }

  @override
  Widget build(BuildContext context) {
    final summary = _exploredSummary(widget.cells);
    final isStreaming = widget.cells.any(
      (cell) =>
          cell.status == TimelineCellStatus.inProgress || cell.isStreaming,
    );
    final label = isStreaming
        ? 'Exploring'
        : summary == null
        ? 'Explored'
        : 'Explored $summary';
    final status = widget.cells.last.status;
    final statusColor = _statusColor(status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: AnimatedContainer(
            duration: AleraTokens.durationFast,
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: _isHovered
                  ? AleraTokens.surfaceVariant
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            ),
            child: InkWell(
              onTap: () => setState(() => _collapsed = !_collapsed),
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
              splashFactory: NoSplash.splashFactory,
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space6,
                  vertical: AleraTokens.space4,
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: AleraTokens.space8),
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: AleraTokens.foregroundMuted,
                                  ),
                            ),
                          ),
                          const SizedBox(width: AleraTokens.space4),
                          AnimatedOpacity(
                            duration: AleraTokens.durationFast,
                            opacity: _isHovered ? 1 : 0,
                            child: SizedBox(
                              width: 14,
                              child: Icon(
                                _collapsed
                                    ? Icons.keyboard_arrow_right
                                    : Icons.keyboard_arrow_down,
                                size: 14,
                                color: AleraTokens.foregroundFaint,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (!_collapsed)
          Padding(
            padding: const EdgeInsets.only(top: AleraTokens.space4),
            child: Column(
              children: <Widget>[
                for (final cell in widget.cells)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AleraTokens.space6),
                    child: _ToolCallCell(
                      key: ValueKey('cluster-item-${cell.id}'),
                      cell: cell,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

String? _exploredSummary(List<TimelineCell> cells) {
  var fileCount = 0;
  var searchCount = 0;

  for (final cell in cells) {
    final bucket = cell.metadata['exploreBucket']?.toString().toLowerCase();
    if (bucket == 'search') {
      searchCount += 1;
      continue;
    }
    if (bucket == 'file') {
      fileCount += 1;
    }
  }

  final parts = <String>[];
  if (fileCount > 0) {
    parts.add('$fileCount ${fileCount == 1 ? 'file' : 'files'}');
  }
  if (searchCount > 0) {
    parts.add('$searchCount ${searchCount == 1 ? 'search' : 'searches'}');
  }

  if (parts.isEmpty) {
    return null;
  }
  return parts.join(', ');
}

class _WorkedForDivider extends StatelessWidget {
  const _WorkedForDivider({
    required this.label,
    required this.expanded,
    required this.onTap,
  });

  final String? label;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey<String>('worked-divider'),
      children: <Widget>[
        const Expanded(
          child: Divider(
            color: AleraTokens.borderSubtle,
            height: 1,
            thickness: 1,
          ),
        ),
        InkWell(
          onTap: onTap,
          mouseCursor: SystemMouseCursors.click,
          borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space12,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label ?? '',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
                const SizedBox(width: AleraTokens.space6),
                Icon(
                  expanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                  size: 14,
                  color: AleraTokens.foregroundFaint,
                ),
              ],
            ),
          ),
        ),
        const Expanded(
          child: Divider(
            color: AleraTokens.borderSubtle,
            height: 1,
            thickness: 1,
          ),
        ),
      ],
    );
  }
}

String? _workedForLabel(TimelineCell separatorCell) {
  final metadata = separatorCell.metadata;
  final hasMetrics = _hasRuntimeMetrics(metadata);
  final formatted = _formatWorkedDuration(metadata);
  if (formatted != null) {
    return 'Worked for $formatted';
  }
  if (hasMetrics) {
    return 'Work finished';
  }
  return null;
}

String? _formatWorkedDuration(Map<String, dynamic> metadata) {
  final durationMs = _durationMs(metadata);
  if (durationMs == null || durationMs <= 0) {
    return null;
  }
  final totalSeconds = (durationMs / 1000).round();
  if (totalSeconds <= 0) {
    return '0s';
  }
  final days = totalSeconds ~/ 86400;
  final hours = (totalSeconds % 86400) ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (days > 0) {
    if (hours > 0) {
      return '${days}d ${hours}h';
    }
    if (minutes > 0) {
      return '${days}d ${minutes}m';
    }
    return '${days}d';
  }
  if (hours > 0) {
    if (minutes > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${hours}h';
  }
  if (minutes > 0) {
    return '${minutes}m ${seconds}s';
  }
  if (totalSeconds < 60) {
    return '${totalSeconds}s';
  }
  return '${totalSeconds}s';
}

num? _durationMs(Map<String, dynamic> metadata) {
  return _asNum(metadata['computedDurationMs']) ??
      _asNum(metadata['computed_duration_ms']) ??
      _asNum(metadata['elapsedMs']) ??
      _asNum(metadata['elapsed_ms']) ??
      _asNum(metadata['durationMs']) ??
      _asNum(metadata['duration_ms']) ??
      _durationFromTimestamps(metadata);
}

bool _hasRuntimeMetrics(Map<String, dynamic> metadata) {
  final runtime = metadata['runtimeMetrics'];
  if (runtime is Map && runtime.isNotEmpty) {
    return true;
  }
  final totalTokens =
      _asNum(metadata['totalTokens']) ??
      _asNum(metadata['total_tokens']) ??
      _asNum(_asMap(metadata['usage'])['totalTokens']) ??
      _asNum(_asMap(metadata['usage'])['total_tokens']);
  return totalTokens != null && totalTokens > 0;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const <String, dynamic>{};
}

num? _durationFromTimestamps(Map<String, dynamic> metadata) {
  final startRaw =
      _asNum(metadata['startedAt']) ??
      _asNum(metadata['started_at']) ??
      _asNum(metadata['createdAt']) ??
      _asNum(metadata['created_at']);
  final endRaw =
      _asNum(metadata['completedAt']) ??
      _asNum(metadata['completed_at']) ??
      _asNum(metadata['updatedAt']) ??
      _asNum(metadata['updated_at']);
  if (startRaw == null || endRaw == null) {
    return null;
  }
  final startMs = _normalizeEpochToMs(startRaw);
  final endMs = _normalizeEpochToMs(endRaw);
  if (endMs < startMs) {
    return null;
  }
  return endMs - startMs;
}

num? _asNum(dynamic value) {
  if (value is num) {
    return value;
  }
  if (value is String) {
    return num.tryParse(value);
  }
  return null;
}

num _normalizeEpochToMs(num raw) {
  // < 10^11 is likely epoch seconds, otherwise milliseconds.
  return raw < 100000000000 ? raw * 1000 : raw;
}

class _UserMessageCell extends StatefulWidget {
  const _UserMessageCell({
    required this.cell,
    required this.markdownEnabled,
    required this.onMarkdownModeChanged,
  });

  final TimelineCell cell;
  final bool markdownEnabled;
  final ValueChanged<bool> onMarkdownModeChanged;

  @override
  State<_UserMessageCell> createState() => _UserMessageCellState();
}

class _UserMessageCellState extends State<_UserMessageCell> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final messageText = widget.cell.markdownText ?? '';
    final showCopy = _isHovered || !_mouseIsConnected();
    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.only(
            top: AleraTokens.space6,
            bottom: AleraTokens.space4,
            left: 80,
          ),
          child: MouseRegion(
            key: ValueKey<String>('copy-zone-user-${widget.cell.id}'),
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Container(
                    key: ValueKey<String>('user-bubble-${widget.cell.id}'),
                    padding: const EdgeInsets.all(AleraTokens.space12),
                    decoration: BoxDecoration(
                      color: AleraTokens.accentSubtle,
                      borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                    ),
                    child: _UserBubbleContent(
                      markdownText: messageText,
                      markdownEnabled: widget.markdownEnabled,
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    ignoring: !showCopy,
                    child: AnimatedOpacity(
                      duration: AleraTokens.durationFast,
                      opacity: showCopy ? 1 : 0,
                      child: _MessageActionButtons(
                        alignLeft: false,
                        copyKey: ValueKey<String>(
                          'copy-user-${widget.cell.id}',
                        ),
                        copyText: messageText,
                        copiedLabel: 'message copied',
                        toggleKey: ValueKey<String>(
                          'toggle-markdown-user-${widget.cell.id}',
                        ),
                        markdownEnabled: widget.markdownEnabled,
                        onToggleMarkdown: widget.onMarkdownModeChanged,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AssistantMessageCell extends StatefulWidget {
  const _AssistantMessageCell({
    required this.cell,
    required this.markdownEnabled,
    required this.onMarkdownModeChanged,
  });

  final TimelineCell cell;
  final bool markdownEnabled;
  final ValueChanged<bool> onMarkdownModeChanged;

  @override
  State<_AssistantMessageCell> createState() => _AssistantMessageCellState();
}

class _AssistantMessageCellState extends State<_AssistantMessageCell> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final rawText = widget.cell.markdownText ?? '';
    if (rawText.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final showCopy = _isHovered || !_mouseIsConnected();

    return Padding(
      padding: const EdgeInsets.only(
        top: AleraTokens.space6,
        bottom: AleraTokens.space4,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: MouseRegion(
            key: ValueKey<String>('copy-zone-assistant-${widget.cell.id}'),
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Container(
                    key: ValueKey<String>('assistant-bubble-${widget.cell.id}'),
                    child: _AssistantBubbleMarkdown(
                      markdownText: rawText,
                      isStreaming: widget.cell.isStreaming,
                      markdownEnabled: widget.markdownEnabled,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    ignoring: !showCopy,
                    child: AnimatedOpacity(
                      duration: AleraTokens.durationFast,
                      opacity: showCopy ? 1 : 0,
                      child: _MessageActionButtons(
                        alignLeft: true,
                        copyKey: ValueKey<String>(
                          'copy-assistant-${widget.cell.id}',
                        ),
                        copyText: rawText,
                        copiedLabel: 'message copied',
                        toggleKey: ValueKey<String>(
                          'toggle-markdown-assistant-${widget.cell.id}',
                        ),
                        markdownEnabled: widget.markdownEnabled,
                        onToggleMarkdown: widget.onMarkdownModeChanged,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
bool Function() copyMouseConnectionDetector = () =>
    RendererBinding.instance.mouseTracker.mouseIsConnected;

bool _mouseIsConnected() => copyMouseConnectionDetector();

class _ProgressTextRow extends StatelessWidget {
  const _ProgressTextRow({required this.cell, required this.markdownEnabled});

  final TimelineCell cell;
  final bool markdownEnabled;

  @override
  Widget build(BuildContext context) {
    final text = (cell.markdownText ?? '').trim();
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    final styleSheet = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: AleraTokens.foregroundMuted),
      strong: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: AleraTokens.foreground,
        fontWeight: FontWeight.w700,
      ),
      em: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: AleraTokens.foregroundMuted,
        fontStyle: FontStyle.italic,
      ),
      code: AleraTokens.monoStyle.copyWith(
        fontSize: 12,
        color: AleraTokens.foreground,
      ),
      codeblockDecoration: BoxDecoration(
        color: AleraTokens.bg,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(color: AleraTokens.border),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final width = maxWidth.isFinite
            ? (maxWidth < 760 ? maxWidth : 760.0)
            : 760.0;
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space6,
                vertical: AleraTokens.space2,
              ),
              child: markdownEnabled
                  ? MarkdownBody(
                      data: text,
                      styleSheet: styleSheet,
                      builders: <String, MarkdownElementBuilder>{
                        'pre': _CodeBlockBuilder(context),
                      },
                      selectable: false,
                    )
                  : Text(
                      text,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _AssistantBubbleMarkdown extends StatelessWidget {
  const _AssistantBubbleMarkdown({
    required this.markdownText,
    required this.isStreaming,
    required this.markdownEnabled,
  });

  final String markdownText;
  final bool isStreaming;
  final bool markdownEnabled;

  @override
  Widget build(BuildContext context) {
    final shouldRenderMarkdown =
        markdownEnabled && !isStreaming && _isMarkdownRenderSafe(markdownText);
    final styleSheet = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: Theme.of(context).textTheme.bodyMedium,
      code: AleraTokens.monoStyle.copyWith(
        fontSize: 12,
        color: AleraTokens.foreground,
      ),
      codeblockDecoration: BoxDecoration(
        color: AleraTokens.bg,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(color: AleraTokens.border),
      ),
      blockquoteDecoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (shouldRenderMarkdown)
          MarkdownBody(
            data: markdownText,
            styleSheet: styleSheet,
            builders: <String, MarkdownElementBuilder>{
              'pre': _CodeBlockBuilder(context),
            },
            selectable: false,
          )
        else
          Text(markdownText, style: Theme.of(context).textTheme.bodyMedium),
        if (isStreaming)
          const Padding(
            padding: EdgeInsets.only(top: AleraTokens.space6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AleraTokens.accent,
                  ),
                ),
                SizedBox(width: AleraTokens.space6),
                Text(
                  'streaming...',
                  style: TextStyle(
                    color: AleraTokens.foregroundFaint,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _UserBubbleContent extends StatelessWidget {
  const _UserBubbleContent({
    required this.markdownText,
    required this.markdownEnabled,
  });

  final String markdownText;
  final bool markdownEnabled;

  @override
  Widget build(BuildContext context) {
    if (markdownEnabled && _isMarkdownRenderSafe(markdownText)) {
      final styleSheet = MarkdownStyleSheet.fromTheme(Theme.of(context))
          .copyWith(
            p: Theme.of(context).textTheme.bodyMedium,
            code: AleraTokens.monoStyle.copyWith(
              fontSize: 12,
              color: AleraTokens.foreground,
            ),
            codeblockDecoration: BoxDecoration(
              color: AleraTokens.bg,
              borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
              border: Border.all(color: AleraTokens.border),
            ),
          );
      return MarkdownBody(
        data: markdownText,
        styleSheet: styleSheet,
        selectable: false,
      );
    }
    return Text(markdownText, style: Theme.of(context).textTheme.bodyMedium);
  }
}

class _MessageActionButtons extends StatelessWidget {
  const _MessageActionButtons({
    required this.alignLeft,
    required this.copyKey,
    required this.copyText,
    required this.copiedLabel,
    required this.toggleKey,
    required this.markdownEnabled,
    required this.onToggleMarkdown,
  });

  final bool alignLeft;
  final ValueKey<String> copyKey;
  final String copyText;
  final String copiedLabel;
  final ValueKey<String> toggleKey;
  final bool markdownEnabled;
  final ValueChanged<bool> onToggleMarkdown;

  @override
  Widget build(BuildContext context) {
    final copy = _MessageCopyButton(
      key: copyKey,
      copyText: copyText,
      copiedLabel: copiedLabel,
    );
    final markdownToggle = _MessageMarkdownToggleButton(
      key: toggleKey,
      markdownEnabled: markdownEnabled,
      onChanged: onToggleMarkdown,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: alignLeft
          ? <Widget>[
              copy,
              const SizedBox(width: AleraTokens.space2),
              markdownToggle,
            ]
          : <Widget>[
              markdownToggle,
              const SizedBox(width: AleraTokens.space2),
              copy,
            ],
    );
  }
}

bool _isMarkdownRenderSafe(String text) {
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (normalized.trim().isEmpty) {
    return false;
  }
  if (!_hasBalancedCodeFences(normalized)) {
    return false;
  }
  if (!_hasBalancedInlineBackticksOutsideFences(normalized)) {
    return false;
  }
  try {
    final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored);
    document.parseLines(normalized.split('\n'));
    return true;
  } catch (_) {
    return false;
  }
}

bool _hasBalancedCodeFences(String text) {
  var count = 0;
  var index = 0;
  while (true) {
    index = text.indexOf('```', index);
    if (index == -1) {
      break;
    }
    count += 1;
    index += 3;
  }
  return count.isEven;
}

bool _hasBalancedInlineBackticksOutsideFences(String text) {
  var inFence = false;
  var inlineBackticks = 0;

  for (var i = 0; i < text.length; i++) {
    if (i + 2 < text.length &&
        text.codeUnitAt(i) == 0x60 &&
        text.codeUnitAt(i + 1) == 0x60 &&
        text.codeUnitAt(i + 2) == 0x60) {
      inFence = !inFence;
      i += 2;
      continue;
    }

    if (!inFence && text.codeUnitAt(i) == 0x60) {
      inlineBackticks += 1;
    }
  }

  return !inFence && inlineBackticks.isEven;
}

class _ReasoningCell extends StatefulWidget {
  const _ReasoningCell({
    super.key,
    required this.cell,
    required this.markdownEnabled,
  });

  final TimelineCell cell;
  final bool markdownEnabled;

  @override
  State<_ReasoningCell> createState() => _ReasoningCellState();
}

class _ReasoningCellState extends State<_ReasoningCell> {
  late bool _collapsed;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _collapsed = widget.cell.isCollapsed;
  }

  @override
  void didUpdateWidget(covariant _ReasoningCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cell.isCollapsed != oldWidget.cell.isCollapsed) {
      _collapsed = widget.cell.isCollapsed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.cell.markdownText ?? '';
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: AnimatedContainer(
              duration: AleraTokens.durationFast,
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: _isHovered
                    ? AleraTokens.surfaceVariant
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
              ),
              child: InkWell(
                onTap: () => setState(() => _collapsed = !_collapsed),
                mouseCursor: SystemMouseCursors.click,
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                splashFactory: NoSplash.splashFactory,
                hoverColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AleraTokens.space6,
                    vertical: AleraTokens.space4,
                  ),
                  child: Row(
                    children: <Widget>[
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                widget.cell.title ?? 'Thinking',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: AleraTokens.foregroundMuted,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: AleraTokens.space4),
                            AnimatedOpacity(
                              duration: AleraTokens.durationFast,
                              opacity: _isHovered ? 1 : 0,
                              child: SizedBox(
                                width: 14,
                                child: Icon(
                                  _collapsed
                                      ? Icons.keyboard_arrow_right
                                      : Icons.keyboard_arrow_down,
                                  size: 14,
                                  color: AleraTokens.foregroundFaint,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.cell.status ==
                          TimelineCellStatus.inProgress) ...<Widget>[
                        const SizedBox(width: AleraTokens.space6),
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.4,
                            color: AleraTokens.foregroundFaint,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (!_collapsed && text.trim().isNotEmpty)
            Container(
              margin: const EdgeInsets.only(
                left: AleraTokens.space8,
                top: AleraTokens.space4,
              ),
              padding: const EdgeInsets.only(left: AleraTokens.space8),
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: AleraTokens.borderSubtle, width: 2),
                ),
              ),
              child: widget.markdownEnabled
                  ? MarkdownBody(
                      data: text,
                      styleSheet:
                          MarkdownStyleSheet.fromTheme(
                            Theme.of(context),
                          ).copyWith(
                            p: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AleraTokens.foregroundMuted,
                            ),
                          ),
                      selectable: false,
                    )
                  : Text(
                      text,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

class _ToolCallCell extends StatefulWidget {
  const _ToolCallCell({super.key, required this.cell});

  final TimelineCell cell;

  @override
  State<_ToolCallCell> createState() => _ToolCallCellState();
}

class _ToolCallCellState extends State<_ToolCallCell> {
  late bool _collapsed;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _collapsed = widget.cell.isCollapsed;
  }

  @override
  void didUpdateWidget(covariant _ToolCallCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cell.isCollapsed != oldWidget.cell.isCollapsed) {
      _collapsed = widget.cell.isCollapsed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = widget.cell.detailsText ?? '';
    final statusColor = _statusColor(widget.cell.status);
    final title = widget.cell.title ?? 'tool call';
    final subtitle = widget.cell.subtitle;
    final rowLabel = (subtitle == null || subtitle.isEmpty)
        ? title
        : '$title · $subtitle';

    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: AnimatedContainer(
              duration: AleraTokens.durationFast,
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: _isHovered
                    ? AleraTokens.surfaceVariant
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
              ),
              child: InkWell(
                onTap: () => setState(() => _collapsed = !_collapsed),
                mouseCursor: SystemMouseCursors.click,
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                splashFactory: NoSplash.splashFactory,
                hoverColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AleraTokens.space6,
                    vertical: AleraTokens.space4,
                  ),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: AleraTokens.space8),
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                rowLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: AleraTokens.foregroundMuted,
                                    ),
                              ),
                            ),
                            const SizedBox(width: AleraTokens.space4),
                            AnimatedOpacity(
                              duration: AleraTokens.durationFast,
                              opacity: _isHovered ? 1 : 0,
                              child: SizedBox(
                                width: 14,
                                child: Icon(
                                  _collapsed
                                      ? Icons.keyboard_arrow_right
                                      : Icons.keyboard_arrow_down,
                                  size: 14,
                                  color: AleraTokens.foregroundFaint,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (!_collapsed && details.trim().isNotEmpty)
            Container(
              margin: const EdgeInsets.only(
                left: AleraTokens.space8,
                top: AleraTokens.space4,
              ),
              padding: const EdgeInsets.all(AleraTokens.space8),
              decoration: BoxDecoration(
                color: AleraTokens.surface,
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                border: Border.all(color: AleraTokens.borderSubtle),
              ),
              child: SelectableText(
                _prettyDetails(details),
                style: AleraTokens.monoStyle.copyWith(
                  color: AleraTokens.foregroundMuted,
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _prettyDetails(String raw) {
    final trimmed = raw.trim();
    if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
      try {
        final decoded = jsonDecode(trimmed);
        return const JsonEncoder.withIndent('  ').convert(decoded);
      } catch (_) {
        return raw;
      }
    }
    return raw;
  }
}

class _SystemNoticeCell extends StatelessWidget {
  const _SystemNoticeCell({required this.cell});

  final TimelineCell cell;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Text(
        cell.markdownText ?? cell.title ?? 'system event',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AleraTokens.foregroundFaint),
      ),
    );
  }
}

class _MessageCopyButton extends StatelessWidget {
  const _MessageCopyButton({
    super.key,
    required this.copyText,
    required this.copiedLabel,
  });

  final String copyText;
  final String copiedLabel;

  Future<void> _copy(BuildContext context) async {
    if (copyText.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: copyText));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(copiedLabel)));
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _copy(context),
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
      child: const Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AleraTokens.space4,
          vertical: AleraTokens.space2,
        ),
        child: Icon(
          Icons.content_copy,
          size: 12,
          color: AleraTokens.foregroundFaint,
        ),
      ),
    );
  }
}

class _MessageMarkdownToggleButton extends StatelessWidget {
  const _MessageMarkdownToggleButton({
    super.key,
    required this.markdownEnabled,
    required this.onChanged,
  });

  final bool markdownEnabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: markdownEnabled ? 'Markdown ON' : 'Markdown OFF',
      child: InkWell(
        onTap: () => onChanged(!markdownEnabled),
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        child: Container(
          decoration: BoxDecoration(
            color: markdownEnabled ? AleraTokens.surfaceVariant : null,
            borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space4,
            vertical: AleraTokens.space2,
          ),
          child: Icon(
            Icons.code,
            size: 13,
            color: markdownEnabled
                ? AleraTokens.foregroundMuted
                : AleraTokens.foregroundFaint,
          ),
        ),
      ),
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  _CodeBlockBuilder(this.context);

  final BuildContext context;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    if (text.trim().isEmpty) {
      return null;
    }
    return _CopyableCodeBlock(code: text);
  }
}

class _CopyableCodeBlock extends StatelessWidget {
  const _CopyableCodeBlock({required this.code});

  final String code;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('code copied')));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AleraTokens.space8),
      decoration: BoxDecoration(
        color: AleraTokens.bg,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(color: AleraTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space8,
              vertical: AleraTokens.space4,
            ),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AleraTokens.borderSubtle),
              ),
            ),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'code',
                    style: TextStyle(
                      color: AleraTokens.foregroundFaint,
                      fontSize: 10,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => _copy(context),
                  mouseCursor: SystemMouseCursors.click,
                  borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AleraTokens.space6,
                      vertical: AleraTokens.space2,
                    ),
                    child: Text(
                      'copy',
                      style: TextStyle(
                        color: AleraTokens.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(AleraTokens.space12),
            child: SelectableText(
              code,
              style: AleraTokens.monoStyle.copyWith(
                color: AleraTokens.foreground,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.textFieldEnabled,
    required this.canSend,
    required this.canStop,
    required this.canChangeModel,
    required this.isBusy,
    required this.isInterrupting,
    required this.activeModelId,
    required this.availableModels,
    required this.onModelChanged,
    required this.activeReasoningEffort,
    required this.supportedReasoningEfforts,
    required this.onReasoningEffortChanged,
    required this.onSend,
    required this.onInterrupt,
  });

  final TextEditingController controller;
  final bool textFieldEnabled;
  final bool canSend;
  final bool canStop;
  final bool canChangeModel;
  final bool isBusy;
  final bool isInterrupting;
  final String activeModelId;
  final List<CodexModelOption> availableModels;
  final ValueChanged<String> onModelChanged;
  final String activeReasoningEffort;
  final List<String> supportedReasoningEfforts;
  final ValueChanged<String> onReasoningEffortChanged;
  final VoidCallback onSend;
  final VoidCallback onInterrupt;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  String get _activeModelLabel {
    for (final model in widget.availableModels) {
      if (model.id == widget.activeModelId) {
        return model.label;
      }
    }
    return widget.activeModelId;
  }

  String get _reasoningLabel =>
      codexReasoningEffortLabel(widget.activeReasoningEffort);

  void _sendFromShortcut() {
    if (!widget.canSend) {
      return;
    }
    widget.onSend();
  }

  void _insertLineBreak() {
    if (!widget.textFieldEnabled) {
      return;
    }
    final value = widget.controller.value;
    final selection = value.selection;
    final start = selection.start < 0 ? value.text.length : selection.start;
    final end = selection.end < 0 ? value.text.length : selection.end;
    final nextText = value.text.replaceRange(start, end, '\n');
    widget.controller.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + 1),
      composing: TextRange.empty,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Column(
        children: <Widget>[
          if (widget.isBusy)
            Padding(
              padding: const EdgeInsets.only(bottom: AleraTokens.space8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                child: const LinearProgressIndicator(
                  minHeight: 2,
                  color: AleraTokens.accent,
                  backgroundColor: AleraTokens.surfaceVariant,
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: AleraTokens.surfaceVariant,
              borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
              border: Border.all(color: AleraTokens.border),
            ),
            child: Column(
              children: <Widget>[
                CallbackShortcuts(
                  // NOTE: Flutter/macOS debug can assert on synthesized Meta
                  // KeyUp events in HardwareKeyboard. This is framework-level;
                  // shortcut behavior here intentionally remains unchanged.
                  bindings: <ShortcutActivator, VoidCallback>{
                    const SingleActivator(LogicalKeyboardKey.enter):
                        _sendFromShortcut,
                    const SingleActivator(
                      LogicalKeyboardKey.enter,
                      shift: true,
                    ): _insertLineBreak,
                  },
                  child: TextField(
                    controller: widget.controller,
                    enabled: widget.textFieldEnabled,
                    minLines: 2,
                    maxLines: 6,
                    textInputAction: TextInputAction.newline,
                    style: Theme.of(context).textTheme.bodyMedium,
                    decoration: const InputDecoration(
                      hintText: 'Ask for follow-up changes',
                      filled: true,
                      fillColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                      contentPadding: EdgeInsets.fromLTRB(
                        AleraTokens.space16,
                        AleraTokens.space16,
                        AleraTokens.space16,
                        AleraTokens.space8,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AleraTokens.space8,
                    0,
                    AleraTokens.space8,
                    AleraTokens.space8,
                  ),
                  child: Row(
                    children: <Widget>[
                      InkWell(
                        onTap: () {},
                        mouseCursor: SystemMouseCursors.click,
                        borderRadius: BorderRadius.circular(
                          AleraTokens.radiusSm,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(AleraTokens.space4),
                          child: Icon(
                            Icons.add,
                            size: 18,
                            color: AleraTokens.foregroundMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: AleraTokens.space4),
                      PopupMenuButton<String>(
                        onSelected: widget.canChangeModel
                            ? widget.onModelChanged
                            : null,
                        enabled: widget.canChangeModel,
                        constraints: const BoxConstraints(minWidth: 220),
                        itemBuilder: (context) => <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            enabled: false,
                            height: 32,
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              'Select model',
                              style: TextStyle(
                                color: AleraTokens.foregroundFaint,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          ...widget.availableModels.map(
                            (model) => _DropdownEntry<String>(
                              value: model.id,
                              label: model.label,
                              selected: model.id == widget.activeModelId,
                            ),
                          ),
                        ],
                        child: _ComposerChip(label: _activeModelLabel),
                      ),
                      const SizedBox(width: AleraTokens.space6),
                      PopupMenuButton<String>(
                        onSelected: widget.canChangeModel
                            ? widget.onReasoningEffortChanged
                            : null,
                        enabled: widget.canChangeModel,
                        itemBuilder: (context) => <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            enabled: false,
                            height: 32,
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              'Select reasoning effort',
                              style: TextStyle(
                                color: AleraTokens.foregroundFaint,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          ...widget.supportedReasoningEfforts.map(
                            (effort) => _DropdownEntry<String>(
                              value: effort,
                              label: codexReasoningEffortLabel(effort),
                              selected: effort == widget.activeReasoningEffort,
                            ),
                          ),
                        ],
                        child: _ComposerChip(label: _reasoningLabel),
                      ),
                      const Spacer(),
                      IconButton(
                        key: const ValueKey<String>(
                          'composer-send-stop-button',
                        ),
                        onPressed: widget.canStop
                            ? (widget.isInterrupting
                                  ? null
                                  : widget.onInterrupt)
                            : (widget.canSend ? widget.onSend : null),
                        mouseCursor: SystemMouseCursors.click,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(
                          backgroundColor: (widget.canSend || widget.canStop)
                              ? AleraTokens.accent
                              : AleraTokens.surface,
                          foregroundColor: (widget.canSend || widget.canStop)
                              ? AleraTokens.onAccent
                              : AleraTokens.foregroundFaint,
                          shape: const CircleBorder(),
                        ),
                        icon: widget.canStop
                            ? (widget.isInterrupting
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.6,
                                        color: AleraTokens.onAccent,
                                      ),
                                    )
                                  : const Icon(Icons.stop, size: 18))
                            : const Icon(Icons.arrow_upward, size: 16),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposerChip extends StatelessWidget {
  const _ComposerChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space8,
          vertical: AleraTokens.space4,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: const TextStyle(
                color: AleraTokens.foregroundMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: AleraTokens.space4),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 14,
              color: AleraTokens.foregroundFaint,
            ),
          ],
        ),
      ),
    );
  }
}

class _DropdownEntry<T> extends PopupMenuEntry<T> {
  const _DropdownEntry({
    required this.value,
    required this.label,
    this.selected = false,
  });

  final T value;
  final String label;
  final bool selected;

  @override
  double get height => 36;

  @override
  bool represents(T? value) => this.value == value;

  @override
  State<_DropdownEntry<T>> createState() => _DropdownEntryState<T>();
}

class _DropdownEntryState<T> extends State<_DropdownEntry<T>> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: InkWell(
        onTap: () => Navigator.of(context).pop(widget.value),
        mouseCursor: SystemMouseCursors.click,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space4,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.label,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (widget.selected)
                const Icon(
                  Icons.check,
                  size: 16,
                  color: AleraTokens.foreground,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RawLog extends StatelessWidget {
  const _RawLog({required this.state, required this.expanded});

  final SessionState state;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AleraTokens.durationMid,
      curve: Curves.easeOut,
      height: expanded ? 140 : 0,
      decoration: BoxDecoration(
        border: expanded
            ? Border(top: BorderSide(color: Theme.of(context).dividerColor))
            : null,
      ),
      child: expanded
          ? ListView.builder(
              reverse: true,
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space12,
                vertical: AleraTokens.space4,
              ),
              itemCount: state.activityLog.length,
              itemBuilder: (context, index) {
                final logIndex = state.activityLog.length - 1 - index;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AleraTokens.space2,
                  ),
                  child: Text(
                    state.activityLog[logIndex],
                    style: AleraTokens.monoStyle.copyWith(
                      color: AleraTokens.foregroundFaint,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            )
          : null,
    );
  }
}

Color _statusColor(TimelineCellStatus status) {
  return switch (status) {
    TimelineCellStatus.inProgress => AleraTokens.accent,
    TimelineCellStatus.completed => AleraTokens.success,
    TimelineCellStatus.failed => AleraTokens.error,
    TimelineCellStatus.declined => AleraTokens.warning,
    TimelineCellStatus.info => AleraTokens.foregroundFaint,
  };
}
