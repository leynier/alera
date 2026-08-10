part of 'mobile_codex_state.dart';

enum MobileCodexPresentationKind { cell, activity, working }

@immutable
class MobileCodexPresentationRow {
  factory MobileCodexPresentationRow.cell(
    MobileCodexTimelineCell value, {
    bool isPreviousPlan = false,
    bool? isTurnActivity,
  }) => MobileCodexPresentationRow._(
    id: 'cell-${value.id}',
    kind: MobileCodexPresentationKind.cell,
    cell: value,
    turnId: value.turnId,
    activityCells: const <MobileCodexTimelineCell>[],
    isPreviousPlan: isPreviousPlan,
    isTurnActivity: isTurnActivity ?? _isVisibleMobileCodexTurnWork(value),
    turnActivityCount: 0,
    startedAt: null,
  );

  const MobileCodexPresentationRow.activity({
    required this.id,
    required this.activityCells,
    required this.turnId,
    required this.turnActivityCount,
  }) : kind = MobileCodexPresentationKind.activity,
       cell = null,
       isPreviousPlan = false,
       isTurnActivity = true,
       startedAt = null;

  const MobileCodexPresentationRow.working({
    required this.id,
    required this.turnId,
    required this.startedAt,
    required this.turnActivityCount,
  }) : kind = MobileCodexPresentationKind.working,
       cell = null,
       activityCells = const <MobileCodexTimelineCell>[],
       isPreviousPlan = false,
       isTurnActivity = false;

  const MobileCodexPresentationRow._({
    required this.id,
    required this.kind,
    required this.cell,
    required this.turnId,
    required this.activityCells,
    required this.isPreviousPlan,
    required this.isTurnActivity,
    required this.turnActivityCount,
    required this.startedAt,
  });

  final String id;
  final MobileCodexPresentationKind kind;
  final MobileCodexTimelineCell? cell;
  final String? turnId;
  final List<MobileCodexTimelineCell> activityCells;
  final bool isPreviousPlan;
  final bool isTurnActivity;
  final int turnActivityCount;
  final DateTime? startedAt;
}

abstract final class MobileCodexTimelineProjection {
  static List<MobileCodexPresentationRow> project(
    List<MobileCodexTimelineCell> cells, {
    required String? activeTurnId,
  }) {
    final rows = <MobileCodexPresentationRow>[];
    final topNotices = <MobileCodexTimelineCell>[];
    final content = <MobileCodexTimelineCell>[];
    for (final cell in cells) {
      if (_isTopNotice(cell)) {
        topNotices.add(cell);
      } else if (!_isEmptyCompletedDiffPlaceholder(cell)) {
        content.add(cell);
      }
    }
    final orderedContent = _placeTurnHeadersAfterPrompts(content);
    content
      ..clear()
      ..addAll(orderedContent);
    rows.addAll(
      topNotices.map(
        (cell) => MobileCodexPresentationRow.cell(cell, isTurnActivity: false),
      ),
    );
    final activityCounts = <String, int>{};
    for (final cell in content) {
      final turnId = cell.turnId;
      if (turnId != null && _isVisibleMobileCodexTurnWork(cell)) {
        activityCounts.update(turnId, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    final headerTurnIds = content
        .where((cell) => cell.kind == 'turnSeparator')
        .map((cell) => cell.turnId)
        .whereType<String>()
        .toSet();
    int collapsibleActivityCount(String? turnId) =>
        turnId != null &&
            (turnId == activeTurnId || headerTurnIds.contains(turnId))
        ? activityCounts[turnId] ?? 0
        : 0;
    final latestPlanIndex = content.lastIndexWhere(
      (cell) => cell.kind == 'plan',
    );
    final activeSeparator = content
        .where(
          (cell) => cell.kind == 'turnSeparator' && cell.turnId == activeTurnId,
        )
        .firstOrNull;
    final activeStartedAt = activeSeparator == null
        ? activeTurnId == null
              ? null
              : _firstTurnTimestamp(content, activeTurnId)
        : _turnStartedAt(activeSeparator);
    var index = 0;
    var workingInserted = false;
    while (index < content.length) {
      final cell = content[index];
      if (cell.kind == 'turnSeparator' && cell.turnId == activeTurnId) {
        index++;
        continue;
      }
      if (!workingInserted &&
          activeTurnId != null &&
          cell.turnId == activeTurnId &&
          (!cell.isUser || cell.metadata['isSteering'] == true) &&
          cell.kind != 'turnSeparator') {
        rows.add(
          MobileCodexPresentationRow.working(
            id: 'working-$activeTurnId',
            turnId: activeTurnId,
            startedAt: activeStartedAt,
            turnActivityCount: collapsibleActivityCount(activeTurnId),
          ),
        );
        workingInserted = true;
      }
      if (_isGroupedActivity(cell)) {
        final activity = <MobileCodexTimelineCell>[];
        final turnId = cell.turnId;
        while (index < content.length &&
            _isGroupedActivity(content[index]) &&
            content[index].turnId == turnId) {
          activity.add(content[index]);
          index++;
        }
        final visible = activity.where((item) => !item.isReasoning).toList();
        if (visible.length == 1) {
          rows.add(
            _cellRow(
              visible.single,
              isPreviousPlan: false,
              turnActivityCount: collapsibleActivityCount(turnId),
            ),
          );
        } else if (visible.isNotEmpty) {
          rows.add(
            MobileCodexPresentationRow.activity(
              id: 'activity-${visible.first.id}',
              turnId: turnId,
              turnActivityCount: collapsibleActivityCount(turnId),
              activityCells: List<MobileCodexTimelineCell>.unmodifiable(
                activity,
              ),
            ),
          );
        }
        continue;
      }
      rows.add(
        _cellRow(
          cell,
          isPreviousPlan: cell.kind == 'plan' && index != latestPlanIndex,
          turnActivityCount: collapsibleActivityCount(cell.turnId),
        ),
      );
      index++;
    }
    if (activeTurnId != null && !workingInserted) {
      rows.add(
        MobileCodexPresentationRow.working(
          id: 'working-$activeTurnId',
          turnId: activeTurnId,
          startedAt: activeStartedAt,
          turnActivityCount: collapsibleActivityCount(activeTurnId),
        ),
      );
    }
    return List<MobileCodexPresentationRow>.unmodifiable(rows);
  }

  static bool _isGroupedActivity(MobileCodexTimelineCell cell) =>
      _isMobileCodexGroupedActivity(cell);

  static MobileCodexPresentationRow _cellRow(
    MobileCodexTimelineCell cell, {
    required bool isPreviousPlan,
    required int turnActivityCount,
  }) => MobileCodexPresentationRow._(
    id: 'cell-${cell.id}',
    kind: MobileCodexPresentationKind.cell,
    cell: cell,
    turnId: cell.turnId,
    activityCells: const <MobileCodexTimelineCell>[],
    isPreviousPlan: isPreviousPlan,
    isTurnActivity: _isVisibleMobileCodexTurnWork(cell),
    turnActivityCount: turnActivityCount,
    startedAt: cell.kind == 'turnSeparator' ? _turnStartedAt(cell) : null,
  );

  static DateTime? _turnStartedAt(MobileCodexTimelineCell separator) =>
      _dateTime(separator.metadata['startedAt']) ?? separator.createdAt;

  static DateTime? _firstTurnTimestamp(
    List<MobileCodexTimelineCell> cells,
    String turnId,
  ) => cells
      .where((cell) => cell.turnId == turnId)
      .map((cell) => cell.createdAt)
      .whereType<DateTime>()
      .firstOrNull;

  static bool _isTopNotice(MobileCodexTimelineCell cell) =>
      cell.metadata['itemType'] == 'mcpServerStartup' ||
      (cell.kind == 'systemNotice' &&
          (cell.status == 'warning' ||
              cell.metadata['severity'] == 'warning' ||
              const <String>{
                'warning',
                'guardianWarning',
                'configWarning',
                'deprecationNotice',
              }.contains(cell.metadata['noticeType'])));

  static List<MobileCodexTimelineCell> _placeTurnHeadersAfterPrompts(
    List<MobileCodexTimelineCell> cells,
  ) {
    final ordered = <MobileCodexTimelineCell>[];
    var index = 0;
    while (index < cells.length) {
      final cell = cells[index];
      if (cell.kind != 'turnSeparator') {
        ordered.add(cell);
        index++;
        continue;
      }
      var promptEnd = index + 1;
      while (cell.turnId != null &&
          promptEnd < cells.length &&
          cells[promptEnd].turnId == cell.turnId &&
          cells[promptEnd].isUser &&
          cells[promptEnd].metadata['isSteering'] != true) {
        ordered.add(cells[promptEnd]);
        promptEnd++;
      }
      ordered.add(cell);
      index = promptEnd;
    }
    return ordered;
  }

  static bool _isEmptyCompletedDiffPlaceholder(MobileCodexTimelineCell cell) {
    if (cell.kind != 'diff' || cell.status != 'completed' || cell.isStreaming) {
      return false;
    }
    final details = (cell.detailsText ?? cell.markdownText ?? '').trim();
    final hasDetails = details.isNotEmpty && details != '[]';
    return !hasDetails && !_hasStructuredChanges(cell.metadata['changes']);
  }

  static bool _hasStructuredChanges(Object? changes) => switch (changes) {
    null => false,
    List<Object?> values => values.isNotEmpty,
    Map<Object?, Object?> values => values.isNotEmpty,
    String value => value.trim().isNotEmpty && value.trim() != '[]',
    _ => true,
  };
}

bool _isMobileCodexGroupedActivity(MobileCodexTimelineCell cell) =>
    cell.isReasoning ||
    cell.kind == 'command' ||
    cell.kind == 'toolCall' ||
    cell.kind == 'diff';

bool _isVisibleMobileCodexTurnWork(MobileCodexTimelineCell cell) =>
    switch (cell.kind) {
      'command' ||
      'toolCall' ||
      'diff' ||
      'subAgent' ||
      'questionAnswer' ||
      'systemNotice' => true,
      'progressText' =>
        cell.metadata['uiPlacement'] != 'outside_worked' &&
            cell.displayText.trim().isNotEmpty,
      _ => false,
    };
