part of 'codex_chat_surface.dart';

class _CodexWorkingIndicator extends StatelessWidget {
  const _CodexWorkingIndicator();

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey<String>('codex-working-indicator'),
    padding: const EdgeInsets.only(bottom: AleraTokens.space12),
    child: Row(
      children: <Widget>[
        _CodexShimmerText(
          text: 'Working',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AleraTokens.foregroundMuted),
        ),
        const SizedBox(width: AleraTokens.space12),
        const Expanded(
          child: Divider(
            color: AleraTokens.borderSubtle,
            height: AleraTokens.dividerExtent,
          ),
        ),
      ],
    ),
  );
}

class _CodexPlanProgressIndicator extends StatelessWidget {
  const _CodexPlanProgressIndicator({required this.progress});

  final _CodexPlanProgressProjection progress;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: AleraHoverCard(
        semanticsLabel: 'Plan Progress',
        hoverDelay: AleraTokens.durationFast,
        mouseCursor: SystemMouseCursors.click,
        card: _CodexPlanProgressCard(steps: progress.steps),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            key: const ValueKey<String>('codex-plan-progress'),
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space16,
              vertical: AleraTokens.space8,
            ),
            decoration: BoxDecoration(
              color: AleraTokens.surfaceVariant,
              borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
              border: Border.all(color: AleraTokens.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox.square(
                  dimension: AleraTokens.iconLg,
                  child: CircularProgressIndicator(
                    value: progress.completed / progress.steps.length,
                    strokeWidth: AleraTokens.strokeThin,
                    color: AleraTokens.info,
                    backgroundColor: AleraTokens.border,
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Text(
                  'Step ${progress.current} / ${progress.steps.length}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
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

class _CodexPlanProgressDock extends StatelessWidget {
  const _CodexPlanProgressDock({required this.progress});

  final _CodexPlanProgressProjection progress;

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey<String>('codex-plan-progress-dock'),
    padding: const EdgeInsets.only(bottom: AleraTokens.space8),
    child: _CodexPlanProgressIndicator(progress: progress),
  );
}

class _CodexPlanProgressProjection {
  const _CodexPlanProgressProjection({
    required this.cell,
    required this.steps,
    required this.current,
    required this.completed,
  });

  static _CodexPlanProgressProjection? fromSnapshot(
    CodexChatSnapshot snapshot,
  ) {
    final activeTurnId = snapshot.activeTurnId;
    if (activeTurnId == null) return null;
    final timelineCells = snapshot.timelineCells;
    final liveCells = timelineCells is CodexTimelineCells
        ? timelineCells.live
        : timelineCells;
    for (final cell in liveCells.reversed) {
      if (cell.kind != CodexTimelineKind.plan ||
          cell.metadata['plan'] is! List ||
          (cell.turnId != null && cell.turnId != activeTurnId)) {
        continue;
      }
      final steps = _codexPlanSteps(cell.metadata['plan']);
      if (steps.isEmpty) return null;
      var active = -1;
      var completed = 0;
      for (var index = 0; index < steps.length; index += 1) {
        final status = steps[index].$2.toLowerCase();
        if (status == 'inprogress' && active < 0) active = index;
        if (status == 'completed') completed += 1;
      }
      return _CodexPlanProgressProjection(
        cell: cell,
        steps: List<(String, String)>.unmodifiable(steps),
        current: active >= 0 ? active + 1 : completed.clamp(1, steps.length),
        completed: completed,
      );
    }
    return null;
  }

  final CodexTimelineCell cell;
  final List<(String, String)> steps;
  final int current;
  final int completed;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _CodexPlanProgressProjection && identical(cell, other.cell);

  @override
  int get hashCode => identityHashCode(cell);
}

class _CodexPlanProgressCard extends StatelessWidget {
  const _CodexPlanProgressCard({required this.steps});

  final List<(String, String)> steps;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey<String>('codex-plan-progress-card'),
    width: AleraTokens.codexPlanProgressCardWidth,
    constraints: const BoxConstraints(
      maxHeight: AleraTokens.codexPlanProgressMaxHeight,
    ),
    padding: const EdgeInsets.all(AleraTokens.space12),
    decoration: BoxDecoration(
      color: AleraTokens.surfaceElevated,
      borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      border: Border.all(color: AleraTokens.border),
    ),
    child: ListView(
      key: const ValueKey<String>('codex-plan-progress-list'),
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      children: <Widget>[
        for (final (step, status) in steps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
            child: Row(
              children: <Widget>[
                Icon(
                  status.toLowerCase() == 'completed'
                      ? AleraIcons.success
                      : AleraIcons.circle,
                  size: AleraTokens.iconMd,
                  color: status.toLowerCase() == 'inprogress'
                      ? AleraTokens.info
                      : AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    step,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

List<(String, String)> _codexPlanSteps(Object? value) {
  if (value is! List) return const <(String, String)>[];
  return <(String, String)>[
    for (final entry in value)
      if (entry is Map && entry['step']?.toString().trim().isNotEmpty == true)
        (
          entry['step'].toString().trim(),
          entry['status']?.toString() ?? 'pending',
        ),
  ];
}
