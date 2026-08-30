part of 'mobile_codex_chat_screen.dart';

class const _MobileCodexGoalBar({
  required final MobileCodexGoal goal,
  required final bool turnActive,
  required final VoidCallback onEdit,
  required final VoidCallback? onPauseResume,
  required final VoidCallback onClear,
}) extends StatefulWidget {
  @override
  State<_MobileCodexGoalBar> createState() => _MobileCodexGoalBarState();
}

class _MobileCodexGoalBarState extends State<_MobileCodexGoalBar> {
  Timer? _ticker;
  late DateTime _observedAt;

  @override
  void initState() {
    super.initState();
    _observedAt = DateTime.now();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _MobileCodexGoalBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.goal.updatedAt != widget.goal.updatedAt ||
        oldWidget.goal.timeUsedSeconds != widget.goal.timeUsedSeconds ||
        oldWidget.goal.status != widget.goal.status ||
        oldWidget.turnActive != widget.turnActive) {
      _observedAt = DateTime.now();
      _syncTicker();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker() {
    _ticker?.cancel();
    if (widget.goal.status != MobileCodexGoalStatus.active ||
        !widget.turnActive) {
      return;
    }
    _ticker = Timer.periodic(AleraTokens.codexElapsedTimeRefreshInterval, (_) {
      if (mounted) setState(() {});
    });
  }

  int get _elapsed {
    if (widget.goal.status != MobileCodexGoalStatus.active ||
        !widget.turnActive) {
      return widget.goal.timeUsedSeconds;
    }
    return widget.goal.timeUsedSeconds +
        DateTime.now().difference(_observedAt).inSeconds;
  }

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey<String>('mobile-codex-goal-bar'),
    color: AleraTokens.surfaceElevated,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      side: const BorderSide(color: AleraTokens.border),
    ),
    child: Padding(
      padding: const EdgeInsets.only(left: AleraTokens.space12),
      child: Row(
        children: <Widget>[
          const Icon(Icons.track_changes_outlined, size: AleraTokens.space16),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              children: <Widget>[
                Text(
                  '${_mobileGoalStatusLabel(widget.goal.status)} • ${_formatMobileGoalElapsed(_elapsed)}',
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                Text(
                  widget.goal.objective,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AleraTokens.foregroundMuted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit Goal',
            onPressed: widget.onEdit,
            icon: const Icon(AleraIcons.edit),
          ),
          if (widget.onPauseResume != null)
            IconButton(
              tooltip: widget.goal.status.canPause
                  ? 'Pause Goal'
                  : 'Resume Goal',
              onPressed: widget.onPauseResume,
              icon: Icon(
                widget.goal.status.canPause
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline,
              ),
            ),
          IconButton(
            tooltip: 'Clear Goal',
            onPressed: widget.onClear,
            icon: const Icon(AleraIcons.delete),
          ),
        ],
      ),
    ),
  );
}

String _mobileGoalStatusLabel(MobileCodexGoalStatus status) => switch (status) {
  MobileCodexGoalStatus.active => 'Pursuing goal',
  MobileCodexGoalStatus.paused => 'Goal paused',
  MobileCodexGoalStatus.blocked => 'Goal stalled',
  MobileCodexGoalStatus.usageLimited => 'Goal hit usage limits',
  MobileCodexGoalStatus.budgetLimited => 'Goal budget reached',
  MobileCodexGoalStatus.complete => 'Goal achieved',
};

String _formatMobileGoalElapsed(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  if (safe < 60) return '${safe}s';
  final minutes = safe ~/ 60;
  if (minutes < 60) return '${minutes}m ${safe % 60}s';
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  if (hours < 24) {
    return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
  }
  return '${hours ~/ 24}d ${hours % 24}h ${remainder}m';
}

Future<String?> _showMobileCodexGoalEditor(
  BuildContext context, {
  required String initialObjective,
}) async {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _MobileCodexGoalEditDialog(initialObjective: initialObjective),
  );
}

class const _MobileCodexGoalEditDialog({required final String initialObjective})
    extends StatefulWidget {
  @override
  State<_MobileCodexGoalEditDialog> createState() =>
      _MobileCodexGoalEditDialogState();
}

class _MobileCodexGoalEditDialogState
    extends State<_MobileCodexGoalEditDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialObjective,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSave {
    final value = _controller.text.trim();
    return value.isNotEmpty && value != widget.initialObjective.trim();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.track_changes_outlined),
    title: const Text('Edit Goal'),
    content: TextField(
      key: const ValueKey<String>('mobile-codex-goal-objective-field'),
      controller: _controller,
      autofocus: true,
      minLines: 5,
      maxLines: 5,
      maxLength: 4000,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(
        hintText: 'Describe the goal Codex should pursue',
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _canSave
            ? () => Navigator.of(context).pop(_controller.text.trim())
            : null,
        child: const Text('Save'),
      ),
    ],
  );
}
