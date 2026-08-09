part of 'codex_chat_surface.dart';

class _WorkedForDivider extends StatelessWidget {
  const _WorkedForDivider({
    required this.label,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AleraTokens.space12),
    child: InkWell(
      key: const ValueKey<String>('worked-divider'),
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
      child: Row(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: AleraTokens.space12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
                const SizedBox(width: AleraTokens.space6),
                Icon(
                  expanded ? AleraIcons.chevronDown : AleraIcons.chevronRight,
                  size: AleraTokens.iconMd,
                  color: AleraTokens.foregroundFaint,
                ),
              ],
            ),
          ),
          const Expanded(
            child: Divider(
              color: AleraTokens.borderSubtle,
              height: AleraTokens.dividerExtent,
            ),
          ),
        ],
      ),
    ),
  );
}

String _workedFor(List<CodexTimelineCell> cells) {
  final separator = cells
      .where((cell) => cell.kind == CodexTimelineKind.turnSeparator)
      .firstOrNull;
  final metadata = separator?.metadata ?? const <String, Object?>{};
  final duration = _number(metadata, <String>[
    'computedDurationMs',
    'computed_duration_ms',
    'elapsedMs',
    'elapsed_ms',
    'durationMs',
    'duration_ms',
  ]);
  final milliseconds = duration?.round() ?? _cellDuration(cells).inMilliseconds;
  final seconds = (milliseconds / 1000).round();
  if (seconds < 60) return 'Worked for ${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return 'Worked for ${minutes}m ${seconds % 60}s';
  return 'Worked for ${minutes ~/ 60}h ${minutes % 60}m';
}

Duration _cellDuration(List<CodexTimelineCell> cells) {
  if (cells.isEmpty) return Duration.zero;
  final started = cells
      .map((cell) => cell.createdAt)
      .reduce((left, right) => left.isBefore(right) ? left : right);
  final finished = cells
      .map((cell) => cell.updatedAt)
      .reduce((left, right) => left.isAfter(right) ? left : right);
  return finished.difference(started);
}

num? _number(Map<String, Object?> values, List<String> keys) {
  for (final key in keys) {
    final value = values[key];
    if (value is num) return value;
  }
  return null;
}

List<List<CodexTimelineCell>> _secondaryRows(List<CodexTimelineCell> cells) {
  final rows = <List<CodexTimelineCell>>[];
  for (final cell in cells) {
    if (_isWorkedActionCell(cell) &&
        rows.isNotEmpty &&
        _isWorkedActionCell(rows.last.last)) {
      rows.last.add(cell);
    } else {
      rows.add(<CodexTimelineCell>[cell]);
    }
  }
  return rows;
}

bool _isWorkedActionCell(CodexTimelineCell cell) =>
    cell.kind == CodexTimelineKind.command ||
    cell.kind == CodexTimelineKind.diff ||
    switch (cell.metadata['itemType']?.toString().toLowerCase()) {
      'websearch' || 'imageview' => true,
      _ => false,
    };

CodexTimelineCell? _latestCodexTurnActivity(List<CodexTimelineCell> cells) {
  for (final cell in cells.reversed) {
    switch (cell.kind) {
      case CodexTimelineKind.userMessage ||
          CodexTimelineKind.reasoning ||
          CodexTimelineKind.turnSeparator ||
          CodexTimelineKind.systemNotice:
        continue;
      case CodexTimelineKind.assistantMessage || CodexTimelineKind.progressText:
        final text = cell.renderedMarkdownText ?? cell.markdownText ?? '';
        if (text.trim().isEmpty) continue;
        return cell;
      case CodexTimelineKind.toolCall ||
          CodexTimelineKind.command ||
          CodexTimelineKind.diff ||
          CodexTimelineKind.subAgent ||
          CodexTimelineKind.plan ||
          CodexTimelineKind.questionAnswer:
        return cell;
    }
  }
  return null;
}
