part of 'mobile_codex_state.dart';

enum MobileCodexPresentationKind { cell, activity, working }

@immutable
class MobileCodexPresentationRow {
  factory MobileCodexPresentationRow.cell(
    MobileCodexTimelineCell value, {
    bool isPreviousPlan = false,
  }) => MobileCodexPresentationRow._(
    id: 'cell-${value.id}',
    kind: MobileCodexPresentationKind.cell,
    cell: value,
    activityCells: const <MobileCodexTimelineCell>[],
    isPreviousPlan: isPreviousPlan,
  );

  const MobileCodexPresentationRow.activity({
    required this.id,
    required this.activityCells,
  }) : kind = MobileCodexPresentationKind.activity,
       cell = null,
       isPreviousPlan = false;

  const MobileCodexPresentationRow.working({required this.id})
    : kind = MobileCodexPresentationKind.working,
      cell = null,
      activityCells = const <MobileCodexTimelineCell>[],
      isPreviousPlan = false;

  const MobileCodexPresentationRow._({
    required this.id,
    required this.kind,
    required this.cell,
    required this.activityCells,
    required this.isPreviousPlan,
  });

  final String id;
  final MobileCodexPresentationKind kind;
  final MobileCodexTimelineCell? cell;
  final List<MobileCodexTimelineCell> activityCells;
  final bool isPreviousPlan;
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
    rows.addAll(topNotices.map(MobileCodexPresentationRow.cell));
    final latestPlanIndex = content.lastIndexWhere(
      (cell) => cell.kind == 'plan',
    );
    var index = 0;
    var workingInserted = false;
    while (index < content.length) {
      final cell = content[index];
      if (!workingInserted &&
          activeTurnId != null &&
          cell.turnId == activeTurnId &&
          !cell.isUser &&
          cell.kind != 'turnSeparator') {
        rows.add(
          MobileCodexPresentationRow.working(id: 'working-$activeTurnId'),
        );
        workingInserted = true;
      }
      if (_isActivity(cell)) {
        final activity = <MobileCodexTimelineCell>[];
        final turnId = cell.turnId;
        while (index < content.length &&
            _isActivity(content[index]) &&
            content[index].turnId == turnId) {
          activity.add(content[index]);
          index++;
        }
        final visible = activity.where((item) => !item.isReasoning).toList();
        if (visible.length == 1) {
          rows.add(MobileCodexPresentationRow.cell(visible.single));
        } else if (visible.isNotEmpty) {
          rows.add(
            MobileCodexPresentationRow.activity(
              id: 'activity-${visible.first.id}',
              activityCells: List<MobileCodexTimelineCell>.unmodifiable(
                activity,
              ),
            ),
          );
        }
        continue;
      }
      rows.add(
        MobileCodexPresentationRow.cell(
          cell,
          isPreviousPlan: cell.kind == 'plan' && index != latestPlanIndex,
        ),
      );
      index++;
    }
    if (activeTurnId != null && !workingInserted) {
      rows.add(MobileCodexPresentationRow.working(id: 'working-$activeTurnId'));
    }
    return List<MobileCodexPresentationRow>.unmodifiable(rows);
  }

  static bool _isActivity(MobileCodexTimelineCell cell) =>
      cell.isReasoning ||
      cell.kind == 'command' ||
      cell.kind == 'toolCall' ||
      cell.kind == 'diff';

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
