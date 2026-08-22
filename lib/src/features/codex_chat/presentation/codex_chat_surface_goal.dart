part of 'codex_chat_surface.dart';

class _CodexGoalBar extends StatefulWidget {
  const _CodexGoalBar({
    required this.goal,
    required this.turnActive,
    required this.onEdit,
    required this.onPauseResume,
    required this.onClear,
  });

  final CodexThreadGoal goal;
  final bool turnActive;
  final VoidCallback onEdit;
  final VoidCallback? onPauseResume;
  final VoidCallback onClear;

  @override
  State<_CodexGoalBar> createState() => _CodexGoalBarState();
}

class _CodexGoalBarState extends State<_CodexGoalBar> {
  Timer? _ticker;
  late DateTime _observedAt;

  @override
  void initState() {
    super.initState();
    _observedAt = DateTime.now();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _CodexGoalBar oldWidget) {
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
    if (widget.goal.status != CodexThreadGoalStatus.active ||
        !widget.turnActive) {
      _ticker = null;
      return;
    }
    _ticker = Timer.periodic(AleraTokens.codexElapsedTimeRefreshInterval, (_) {
      if (mounted) setState(() {});
    });
  }

  int get _elapsedSeconds {
    final base = widget.goal.timeUsedSeconds;
    if (widget.goal.status != CodexThreadGoalStatus.active ||
        !widget.turnActive) {
      return base;
    }
    return base + DateTime.now().difference(_observedAt).inSeconds;
  }

  @override
  Widget build(BuildContext context) {
    final canPause = widget.goal.status.canPause;
    final canResume = widget.goal.status.canResume;
    return Container(
      key: const ValueKey<String>('codex-goal-bar'),
      height: AleraTokens.space48,
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space12,
        AleraTokens.space6,
        AleraTokens.space8,
        AleraTokens.space12,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceElevated,
        border: Border.all(color: AleraTokens.border),
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.track_changes_outlined,
            size: AleraTokens.iconMd,
            color: AleraTokens.foregroundMuted,
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Row(
              children: <Widget>[
                Text(
                  _goalStatusLabel(widget.goal.status),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AleraTokens.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: AleraTokens.space6),
                Flexible(
                  child: Text(
                    widget.goal.objective,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ),
                const SizedBox(width: AleraTokens.space6),
                Text(
                  '• ${formatCodexGoalElapsed(_elapsedSeconds)}',
                  key: const ValueKey<String>('codex-goal-elapsed'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              ],
            ),
          ),
          _CodexGoalAction(
            key: const ValueKey<String>('codex-goal-edit'),
            tooltip: 'Edit Goal',
            icon: AleraIcons.edit,
            onPressed: widget.onEdit,
          ),
          if (canPause || canResume)
            _CodexGoalAction(
              key: const ValueKey<String>('codex-goal-pause-resume'),
              tooltip: canPause ? 'Pause Goal' : 'Resume Goal',
              icon: canPause
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline,
              onPressed: widget.onPauseResume,
            ),
          _CodexGoalAction(
            key: const ValueKey<String>('codex-goal-clear'),
            tooltip: 'Clear Goal',
            icon: AleraIcons.delete,
            onPressed: widget.onClear,
          ),
        ],
      ),
    );
  }
}

class _CodexGoalAction extends StatelessWidget {
  const _CodexGoalAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    visualDensity: VisualDensity.compact,
    iconSize: AleraTokens.iconMd,
    color: AleraTokens.foregroundMuted,
    onPressed: onPressed,
    icon: Icon(icon),
  );
}

String _goalStatusLabel(CodexThreadGoalStatus status) => switch (status) {
  CodexThreadGoalStatus.active => 'Pursuing goal',
  CodexThreadGoalStatus.paused => 'Goal paused',
  CodexThreadGoalStatus.blocked => 'Goal stalled',
  CodexThreadGoalStatus.usageLimited => 'Goal hit usage limits',
  CodexThreadGoalStatus.budgetLimited => 'Goal budget reached',
  CodexThreadGoalStatus.complete => 'Goal achieved',
};

String formatCodexGoalElapsed(int totalSeconds) {
  final safeSeconds = totalSeconds < 0 ? 0 : totalSeconds;
  if (safeSeconds < 60) return '${safeSeconds}s';
  final minutes = safeSeconds ~/ 60;
  if (minutes < 60) return '${minutes}m ${safeSeconds % 60}s';
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  if (hours < 24) {
    return remainingMinutes == 0
        ? '${hours}h'
        : '${hours}h ${remainingMinutes}m';
  }
  final days = hours ~/ 24;
  final remainingHours = hours % 24;
  return '${days}d ${remainingHours}h ${remainingMinutes}m';
}

Future<String?> _showCodexGoalEditor(
  BuildContext context, {
  required String initialObjective,
}) async {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _CodexGoalEditDialog(initialObjective: initialObjective),
  );
}

class _CodexGoalEditDialog extends StatefulWidget {
  const _CodexGoalEditDialog({required this.initialObjective});

  final String initialObjective;

  @override
  State<_CodexGoalEditDialog> createState() => _CodexGoalEditDialogState();
}

class _CodexGoalEditDialogState extends State<_CodexGoalEditDialog> {
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
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: AleraTokens.dialogCompactWidth,
        maxWidth: AleraTokens.dialogCompactWidth,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: AleraTokens.space48,
                  height: AleraTokens.space48,
                  decoration: BoxDecoration(
                    color: AleraTokens.surfaceVariant,
                    borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                  ),
                  child: const Icon(
                    Icons.track_changes_outlined,
                    size: AleraTokens.iconLg,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Cancel',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(AleraIcons.close),
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space16),
            Text('Edit Goal', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AleraTokens.space16),
            TextField(
              key: const ValueKey<String>('codex-goal-objective-field'),
              controller: _controller,
              autofocus: true,
              minLines: 6,
              maxLines: 6,
              maxLength: 4000,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Describe the goal Codex should pursue',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AleraTokens.space12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AleraTokens.space8),
                FilledButton(
                  key: const ValueKey<String>('codex-goal-save'),
                  onPressed: _canSave
                      ? () => Navigator.of(context).pop(_controller.text.trim())
                      : null,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
