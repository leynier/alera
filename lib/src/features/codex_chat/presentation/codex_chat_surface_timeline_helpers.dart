part of 'codex_chat_surface.dart';

class _WorkedForDivider extends StatefulWidget {
  const _WorkedForDivider({
    required this.label,
    required this.expanded,
    required this.working,
    required this.startedAt,
    required this.canToggle,
    required this.onTap,
  });

  final String label;
  final bool expanded;
  final bool working;
  final DateTime? startedAt;
  final bool canToggle;
  final VoidCallback onTap;

  @override
  State<_WorkedForDivider> createState() => _WorkedForDividerState();
}

class _WorkedForDividerState extends State<_WorkedForDivider>
    with WidgetsBindingObserver {
  Timer? _elapsedTimer;
  bool _tickerEnabled = false;
  bool _applicationActive = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncElapsedTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncElapsedTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _applicationActive = state == AppLifecycleState.resumed;
    _syncElapsedTimer();
  }

  @override
  void didUpdateWidget(covariant _WorkedForDivider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.working != widget.working ||
        oldWidget.startedAt != widget.startedAt) {
      _syncElapsedTimer();
    }
  }

  void _syncElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer =
        widget.working &&
            widget.startedAt != null &&
            _tickerEnabled &&
            _applicationActive
        ? Timer.periodic(AleraTokens.codexElapsedTimeRefreshInterval, (_) {
            if (mounted) setState(() {});
          })
        : null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _elapsedTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AleraTokens.space12),
    child: InkWell(
      key: ValueKey<String>(
        widget.working ? 'codex-working-indicator' : 'worked-divider',
      ),
      onTap: widget.canToggle ? widget.onTap : null,
      mouseCursor: widget.canToggle
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
      child: Row(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: AleraTokens.space12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (widget.working)
                  _CodexShimmerText(
                    text: widget.startedAt == null
                        ? 'Working'
                        : _workingFor(widget.startedAt!, DateTime.now()),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  )
                else
                  Text(
                    widget.label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                if (widget.canToggle) ...<Widget>[
                  const SizedBox(width: AleraTokens.space6),
                  Icon(
                    widget.expanded
                        ? AleraIcons.chevronDown
                        : AleraIcons.chevronRight,
                    size: AleraTokens.iconMd,
                    color: AleraTokens.foregroundFaint,
                  ),
                ],
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
  final cellDuration = _cellDuration(cells);
  final milliseconds = duration != null && duration.isFinite && duration >= 0
      ? duration.round()
      : cellDuration?.inMilliseconds;
  if (milliseconds == null) return 'Worked';
  return 'Worked for ${_codexDurationText(milliseconds)}';
}

String _workingFor(DateTime startedAt, DateTime now) {
  final milliseconds = now
      .difference(startedAt)
      .inMilliseconds
      .clamp(0, 1 << 31);
  return 'Working for ${_codexDurationText(milliseconds)}';
}

String _codexDurationText(int milliseconds) {
  final seconds = (milliseconds / 1000).round();
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ${seconds % 60}s';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

DateTime? _codexTurnStartedAt(List<CodexTimelineCell> cells) {
  final timestamps = cells
      .map((cell) => cell.createdAt)
      .where((value) => value.millisecondsSinceEpoch > 0);
  if (timestamps.isEmpty) return null;
  return timestamps.reduce(
    (left, right) => left.isBefore(right) ? left : right,
  );
}

Duration? _cellDuration(List<CodexTimelineCell> cells) {
  if (cells.isEmpty) return null;
  final created = cells
      .map((cell) => cell.createdAt)
      .where((value) => value.millisecondsSinceEpoch > 0);
  final updated = cells
      .map((cell) => cell.updatedAt)
      .where((value) => value.millisecondsSinceEpoch > 0);
  if (created.isEmpty || updated.isEmpty) return null;
  final started = created.reduce(
    (left, right) => left.isBefore(right) ? left : right,
  );
  final finished = updated.reduce(
    (left, right) => left.isAfter(right) ? left : right,
  );
  if (finished.isBefore(started)) return null;
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
