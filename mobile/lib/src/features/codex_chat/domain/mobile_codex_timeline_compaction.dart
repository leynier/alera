part of 'mobile_codex_state.dart';

List<MobileCodexTimelineCell> _reduceLegacyMobileContextCompaction(
  List<MobileCodexTimelineCell> cells,
  String turnId,
) {
  if (turnId.isEmpty) return cells;
  final index = cells.lastIndexWhere(
    (cell) => cell.turnId == turnId && isMobileCodexContextCompaction(cell),
  );
  if (index >= 0) {
    return <MobileCodexTimelineCell>[
      for (var position = 0; position < cells.length; position++)
        position == index
            ? cells[position].copyWith(
                status: 'completed',
                title: 'Compacted',
                isStreaming: false,
              )
            : cells[position],
    ];
  }
  return <MobileCodexTimelineCell>[
    ...cells,
    MobileCodexTimelineCell(
      id: 'compaction-$turnId',
      turnId: turnId,
      kind: 'toolCall',
      status: 'completed',
      title: 'Compacted',
      metadata: const <String, Object?>{'itemType': 'contextCompaction'},
    ),
  ];
}

String mobileCodexContextCompactionTitle(String status) => switch (status) {
  'failed' => 'Compaction failed',
  'completed' => 'Compacted',
  _ => 'Compacting',
};
