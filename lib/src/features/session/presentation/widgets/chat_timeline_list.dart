import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/session/domain/chat_timeline.dart';
import 'package:alera/src/features/session/presentation/widgets/timeline_cells.dart';
import 'package:alera/src/features/session/presentation/widgets/worked_for_divider.dart';
import 'package:flutter/material.dart';

class ChatTimelineList extends StatelessWidget {
  const ChatTimelineList({
    super.key,
    required this.state,
    required this.expandedWorkedTurns,
    required this.onToggleWorkedTurn,
    required this.controller,
    required this.markdownEnabled,
    required this.onMarkdownModeChanged,
    required this.contentMaxWidth,
    required this.showImplementPlanButton,
    required this.onImplementPlanPressed,
  });

  final SessionState state;
  final Set<String> expandedWorkedTurns;
  final ValueChanged<String> onToggleWorkedTurn;
  final ScrollController controller;
  final bool markdownEnabled;
  final ValueChanged<bool> onMarkdownModeChanged;
  final double contentMaxWidth;
  final bool showImplementPlanButton;
  final VoidCallback onImplementPlanPressed;

  @override
  Widget build(BuildContext context) {
    if (state.timelineCells.isEmpty) {
      return EmptyChatState(state: state);
    }
    final items = _buildTimelineItems();
    final itemCount = items.length + (showImplementPlanButton ? 1 : 0);

    return SelectionArea(
      child: ListView.builder(
        key: const ValueKey<String>('timeline-list'),
        controller: controller,
        padding: const EdgeInsets.all(AleraTokens.space16),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          final Widget child;
          if (index < items.length) {
            child = _buildTimelineItem(items[index]);
          } else {
            child = Padding(
              padding: const EdgeInsets.only(bottom: AleraTokens.space8),
              child: Align(
                alignment: Alignment.center,
                child: FilledButton(
                  key: const ValueKey<String>('implement-plan-button'),
                  onPressed: onImplementPlanPressed,
                  child: const Text('Implement plan'),
                ),
              ),
            );
          }

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentMaxWidth),
              child: child,
            ),
          );
        },
      ),
    );
  }

  Widget _buildTimelineItem(_TimelineItem item) {
    return switch (item) {
      _CellItem(cell: final cell) => _timelineCellWithSpacing(cell),
      _ClusterItem(cells: final cluster) => Padding(
        padding: const EdgeInsets.only(bottom: AleraTokens.space8),
        child: ExploringClusterCell(
          key: ValueKey('cluster-open-${cluster.first.id}-${cluster.last.id}'),
          cells: cluster,
        ),
      ),
      _TurnItem(
        turnId: final turnId,
        separator: final separator,
        turnCells: final turnCells,
      ) =>
        Padding(
          padding: const EdgeInsets.only(bottom: AleraTokens.space8),
          child: CompletedTurnSection(
            turnId: turnId,
            separator: separator,
            turnCells: turnCells,
            workedExpanded: expandedWorkedTurns.contains(turnId),
            onToggleWorked: () => onToggleWorkedTurn(turnId),
            markdownEnabled: markdownEnabled,
            onMarkdownModeChanged: onMarkdownModeChanged,
          ),
        ),
    };
  }

  List<_TimelineItem> _buildTimelineItems() {
    final cells = state.timelineCells;
    final separatorsByTurn = <String, TimelineCell>{};
    final firstIndexByTurn = <String, int>{};
    final turnCellsMap = <String, List<TimelineCell>>{};

    for (var i = 0; i < cells.length; i++) {
      final cell = cells[i];
      final turnId = cell.turnId;
      if (turnId != null) {
        firstIndexByTurn.putIfAbsent(turnId, () => i);
        if (cell.kind == TimelineCellKind.turnSeparator) {
          separatorsByTurn[turnId] = cell;
        } else {
          turnCellsMap.putIfAbsent(turnId, () => []).add(cell);
        }
      }
    }

    final renderedCompletedTurns = <String>{};
    final items = <_TimelineItem>[];
    for (var i = 0; i < cells.length; i++) {
      final cell = cells[i];
      final turnId = cell.turnId;
      if (turnId == null) {
        if (cell.kind == TimelineCellKind.turnSeparator) {
          continue;
        }
        items.add(_CellItem(cell));
        continue;
      }
      final separator = separatorsByTurn[turnId];
      final isCompletedTurn = separator != null;
      if (!isCompletedTurn) {
        if (cell.kind == TimelineCellKind.turnSeparator) {
          continue;
        }
        if (isExploratoryToolCell(cell)) {
          final runLength = _exploratoryRunLength(cells, i);
          if (runLength >= 2) {
            final cluster = cells.sublist(i, i + runLength);
            items.add(_ClusterItem(cluster));
            i += runLength - 1;
            continue;
          }
        }
        items.add(_CellItem(cell));
        continue;
      }
      final firstTurnIndex = firstIndexByTurn[turnId];
      if (firstTurnIndex != i || renderedCompletedTurns.contains(turnId)) {
        continue;
      }
      renderedCompletedTurns.add(turnId);
      final turnCells = turnCellsMap[turnId] ?? const <TimelineCell>[];
      items.add(
        _TurnItem(turnId: turnId, separator: separator, turnCells: turnCells),
      );
    }
    return items;
  }

  Widget _timelineCellWithSpacing(TimelineCell cell) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space8),
      child: TimelineCellView(
        cell: cell,
        markdownEnabled: markdownEnabled,
        onMarkdownModeChanged: onMarkdownModeChanged,
      ),
    );
  }

  int _exploratoryRunLength(List<TimelineCell> cells, int startIndex) {
    final start = cells[startIndex];
    if (!isExploratoryToolCell(start)) {
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
      if (!isExploratoryToolCell(candidate)) {
        break;
      }
      current += 1;
    }
    return current - startIndex;
  }
}

class EmptyChatState extends StatelessWidget {
  const EmptyChatState({super.key, required this.state});

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
            session?.title ?? 'New session',
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
            'Start the conversation by sending a message',
            style: TextStyle(color: AleraTokens.foregroundFaint),
          ),
        ],
      ),
    );
  }
}

class SecondaryRenderRow {
  SecondaryRenderRow.single(this.cell) : clusterCells = null;

  SecondaryRenderRow.cluster(List<TimelineCell> cells)
    : cell = null,
      clusterCells = List<TimelineCell>.unmodifiable(cells);

  final TimelineCell? cell;
  final List<TimelineCell>? clusterCells;

  bool get isCluster => clusterCells != null;
}

List<SecondaryRenderRow> buildSecondaryRows(List<TimelineCell> cells) {
  final rows = <SecondaryRenderRow>[];
  final renderable = cells
      .where(_isRenderableSecondaryCell)
      .toList(growable: false);
  var index = 0;
  while (index < renderable.length) {
    final cell = renderable[index];
    if (isExploratoryToolCell(cell)) {
      var end = index + 1;
      while (end < renderable.length &&
          isExploratoryToolCell(renderable[end])) {
        end += 1;
      }
      final sequence = renderable.sublist(index, end);
      if (sequence.length >= 2) {
        rows.add(SecondaryRenderRow.cluster(sequence));
      } else {
        rows.add(SecondaryRenderRow.single(cell));
      }
      index = end;
      continue;
    }
    rows.add(SecondaryRenderRow.single(cell));
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

class SecondaryRowView extends StatelessWidget {
  const SecondaryRowView({
    super.key,
    required this.row,
    required this.markdownEnabled,
    required this.onMarkdownModeChanged,
  });

  final SecondaryRenderRow row;
  final bool markdownEnabled;
  final ValueChanged<bool> onMarkdownModeChanged;

  @override
  Widget build(BuildContext context) {
    if (row.isCluster) {
      return ExploringClusterCell(
        key: ValueKey(
          'cluster-${row.clusterCells!.first.id}-${row.clusterCells!.last.id}',
        ),
        cells: row.clusterCells!,
      );
    }
    return TimelineCellView(
      cell: row.cell!,
      markdownEnabled: markdownEnabled,
      onMarkdownModeChanged: onMarkdownModeChanged,
    );
  }
}

class CompletedTurnSection extends StatelessWidget {
  const CompletedTurnSection({
    super.key,
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
    final postTurnRows = <TimelineCell>[];
    for (final cell in turnCells) {
      final placement = _uiPlacement(cell);
      switch (cell.kind) {
        case TimelineCellKind.userMessage:
          if (cell.metadata[TimelineCellMetadata.isSteeringKey] == true) {
            assistants.add(cell);
          } else {
            users.add(cell);
          }
        case TimelineCellKind.assistantMessage:
          assistants.add(cell);
        case TimelineCellKind.progressText:
          if (placement == TimelineCellMetadata.outsideWorked) {
            postTurnRows.add(cell);
          } else {
            secondary.add(cell);
          }
        case TimelineCellKind.plan:
          assistants.add(cell);
        case TimelineCellKind.reasoning ||
            TimelineCellKind.toolCall ||
            TimelineCellKind.subAgent:
          secondary.add(cell);
        case TimelineCellKind.questionAnswer:
          secondary.add(cell);
        case TimelineCellKind.systemNotice:
          if (placement == TimelineCellMetadata.outsideWorked) {
            postTurnRows.add(cell);
          } else {
            secondary.add(cell);
          }
        case TimelineCellKind.turnSeparator:
          break;
      }
    }
    final secondaryRows = buildSecondaryRows(secondary);
    final shouldRenderWorked = secondaryRows.length > 1;
    final shouldRenderSingleSecondary = secondaryRows.length == 1;
    final workedLabel = shouldRenderWorked ? workedForLabel(separator) : null;
    final effectiveWorkedExpanded = workedLabel == null ? true : workedExpanded;
    final children = <Widget>[
      for (final userCell in users)
        Padding(
          key: ValueKey('u-${userCell.id}'),
          padding: const EdgeInsets.only(bottom: AleraTokens.space8),
          child: TimelineCellView(
            cell: userCell,
            markdownEnabled: markdownEnabled,
            onMarkdownModeChanged: onMarkdownModeChanged,
          ),
        ),
    ];
    if (shouldRenderWorked && workedLabel != null) {
      children.add(
        WorkedForDivider(
          key: ValueKey('worked-$turnId'),
          label: workedLabel,
          expanded: effectiveWorkedExpanded,
          onTap: onToggleWorked,
        ),
      );
      if (effectiveWorkedExpanded) {
        children.add(
          Padding(
            key: ValueKey('secondary-$turnId'),
            padding: const EdgeInsets.only(top: AleraTokens.space8),
            child: Column(
              children: <Widget>[
                for (final row in secondaryRows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AleraTokens.space6),
                    child: SecondaryRowView(
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
          key: ValueKey('secondary-nolabel-$turnId'),
          padding: const EdgeInsets.only(bottom: AleraTokens.space8),
          child: Column(
            children: <Widget>[
              for (final row in secondaryRows)
                Padding(
                  padding: const EdgeInsets.only(bottom: AleraTokens.space6),
                  child: SecondaryRowView(
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
          key: ValueKey('single-secondary-$turnId'),
          padding: const EdgeInsets.only(bottom: AleraTokens.space8),
          child: SecondaryRowView(
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
          key: ValueKey('a-${assistantCell.id}'),
          padding: const EdgeInsets.only(bottom: AleraTokens.space8),
          child: TimelineCellView(
            cell: assistantCell,
            markdownEnabled: markdownEnabled,
            onMarkdownModeChanged: onMarkdownModeChanged,
          ),
        ),
      ),
    );
    children.addAll(
      postTurnRows.map(
        (rowCell) => Padding(
          key: ValueKey('p-${rowCell.id}'),
          padding: const EdgeInsets.only(bottom: AleraTokens.space8),
          child: TimelineCellView(
            cell: rowCell,
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

String _uiPlacement(TimelineCell cell) {
  return (cell.metadata[TimelineCellMetadata.uiPlacementKey] ?? '')
      .toString()
      .trim();
}

sealed class _TimelineItem {}

class _CellItem extends _TimelineItem {
  _CellItem(this.cell);
  final TimelineCell cell;
}

class _ClusterItem extends _TimelineItem {
  _ClusterItem(this.cells);
  final List<TimelineCell> cells;
}

class _TurnItem extends _TimelineItem {
  _TurnItem({
    required this.turnId,
    required this.separator,
    required this.turnCells,
  });
  final String turnId;
  final TimelineCell separator;
  final List<TimelineCell> turnCells;
}
