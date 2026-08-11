part of 'mobile_codex_chat_screen.dart';

class _MobileWorkedRow extends StatelessWidget {
  const _MobileWorkedRow({
    required this.cell,
    required this.expanded,
    required this.canToggle,
    required this.onToggle,
  });

  final MobileCodexTimelineCell cell;
  final bool expanded;
  final bool canToggle;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final duration = _mobileDuration(
      cell.metadata['computedDurationMs'] ?? cell.metadata['durationMs'],
    );
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AleraTokens.minTapTarget),
      child: Row(
        children: <Widget>[
          Text(
            duration == null ? 'Worked' : 'Worked for $duration',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          if (canToggle) ...<Widget>[
            const SizedBox(width: AleraTokens.space6),
            Icon(
              expanded ? Icons.expand_more : Icons.chevron_right,
              size: AleraTokens.space16,
              color: AleraTokens.foregroundFaint,
            ),
          ],
          const SizedBox(width: AleraTokens.space12),
          const Expanded(child: Divider(color: AleraTokens.borderSubtle)),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space12),
      child: canToggle
          ? InkWell(
              borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
              onTap: onToggle,
              child: content,
            )
          : content,
    );
  }
}

class _MobileWarningNotice extends StatelessWidget {
  const _MobileWarningNotice({required this.cell});

  final MobileCodexTimelineCell cell;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: AleraTokens.space8),
    padding: const EdgeInsets.all(AleraTokens.space12),
    decoration: BoxDecoration(
      color: AleraTokens.warning.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      border: Border.all(color: AleraTokens.warning.withValues(alpha: 0.32)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(Icons.warning_amber_rounded, color: AleraTokens.warning),
        const SizedBox(width: AleraTokens.space8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                cell.title ?? 'Codex Warning',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: AleraTokens.warning),
              ),
              const SizedBox(height: AleraTokens.space2),
              _MobileCodexMarkdown(text: cell.displayText),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MobileMcpStatus extends StatelessWidget {
  const _MobileMcpStatus({required this.cell});

  final MobileCodexTimelineCell cell;

  @override
  Widget build(BuildContext context) {
    final ready = !cell.isStreaming && cell.status != 'failed';
    final details = cell.displayText.trim();
    final showsDetails =
        cell.status == 'failed' && details.isNotEmpty && details != cell.title;
    final tone = cell.status == 'failed'
        ? AleraTokens.error
        : ready
        ? AleraTokens.success
        : AleraTokens.foregroundMuted;
    return Container(
      margin: const EdgeInsets.only(bottom: AleraTokens.space8),
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space8,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: AleraTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.dns_outlined, size: AleraTokens.space16, color: tone),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text(
                  cell.title ?? 'MCP Server',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (cell.isStreaming)
                _MobileCodexShimmerText(
                  text: 'Starting',
                  style: Theme.of(context).textTheme.labelSmall,
                )
              else
                Text(
                  cell.status == 'failed' ? 'Failed' : 'Ready',
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: tone),
                ),
            ],
          ),
          if (showsDetails) ...<Widget>[
            const SizedBox(height: AleraTokens.space6),
            _MobileCodexMarkdown(text: details),
          ],
        ],
      ),
    );
  }
}

bool _isWarning(MobileCodexTimelineCell cell) =>
    cell.kind == 'systemNotice' &&
    (cell.status == 'warning' ||
        cell.status == 'failed' ||
        cell.metadata['severity'] == 'warning');

bool _isMcpStatus(MobileCodexTimelineCell cell) {
  final type = cell.metadata['itemType']?.toString().toLowerCase() ?? '';
  return type.contains('mcpserver') || cell.kind == 'mcpStatus';
}

String? _mobileDuration(Object? raw) {
  final milliseconds = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
  if (milliseconds == null) return null;
  final seconds = (milliseconds / 1000).round();
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return remainder == 0 ? '${minutes}m' : '${minutes}m ${remainder}s';
}
