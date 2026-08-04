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
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      const Expanded(
        child: Divider(
          color: AleraTokens.borderSubtle,
          height: AleraTokens.dividerExtent,
        ),
      ),
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space12),
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
      ),
      const Expanded(
        child: Divider(
          color: AleraTokens.borderSubtle,
          height: AleraTokens.dividerExtent,
        ),
      ),
    ],
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
    if (_isExploratory(cell) &&
        rows.isNotEmpty &&
        _isExploratory(rows.last.last)) {
      rows.last.add(cell);
    } else {
      rows.add(<CodexTimelineCell>[cell]);
    }
  }
  return rows;
}

bool _isExploratory(CodexTimelineCell cell) {
  if (cell.metadata['exploratory'] == true) return true;
  final type = cell.metadata['itemType']?.toString().toLowerCase() ?? '';
  final title = (cell.title ?? '').toLowerCase();
  return type.contains('websearch') ||
      title.contains('read') ||
      title.contains('list') ||
      title.contains('search');
}
