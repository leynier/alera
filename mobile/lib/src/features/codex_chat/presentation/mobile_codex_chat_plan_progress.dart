part of 'mobile_codex_chat_screen.dart';

class const _MobilePlanProgressBadge({
  required final _MobilePlanProgress progress,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
      child: ActionChip(
        avatar: const Icon(Icons.circle_outlined, size: AleraTokens.space16),
        label: Text('Step ${progress.current} / ${progress.total}'),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: ListView.separated(
              shrinkWrap: true,
              padding: AleraTokens.contentPadding,
              itemCount: progress.items.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AleraTokens.space2),
              itemBuilder: (context, index) => _MobilePlanProgressItem(
                item: progress.items[index],
                index: index,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class const _MobilePlanProgressItem({
  required final Map<String, Object?> item,
  required final int index,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final status = item['status']?.toString().toLowerCase();
    final done = status == 'completed' || status == 'done';
    final active = status == 'inprogress' || status == 'in_progress';
    final tone = active ? AleraTokens.info : AleraTokens.foregroundMuted;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AleraTokens.minTapTarget),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
        child: Row(
          children: <Widget>[
            Icon(
              done ? Icons.check : Icons.circle_outlined,
              size: AleraTokens.space16,
              color: done ? AleraTokens.foregroundMuted : tone,
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Text(
                item['step']?.toString() ??
                    item['title']?.toString() ??
                    'Step ${index + 1}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: done
                      ? AleraTokens.foregroundMuted
                      : AleraTokens.foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
