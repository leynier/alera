part of 'codex_chat_surface.dart';

class _CodexSystemNotice extends StatelessWidget {
  const _CodexSystemNotice({required this.cell});

  final CodexTimelineCell cell;

  @override
  Widget build(BuildContext context) {
    final noticeType = cell.metadata['noticeType']?.toString();
    final warning =
        noticeType == 'warning' ||
        noticeType == 'guardianWarning' ||
        noticeType == 'configWarning' ||
        noticeType == 'deprecationNotice';
    final tone = cell.status == CodexTimelineStatus.failed
        ? AleraTokens.error
        : warning
        ? AleraTokens.warning
        : AleraTokens.foregroundFaint;
    final message = cell.markdownText ?? cell.title ?? 'Codex Event';
    if (!warning && cell.status != CodexTimelineStatus.failed) {
      return Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tone),
      );
    }
    return Container(
      key: ValueKey<String>('codex-warning-notice-${cell.id}'),
      margin: const EdgeInsets.only(bottom: AleraTokens.space8),
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space8,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: tone.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(AleraIcons.warning, size: AleraTokens.iconMd, color: tone),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  cell.title ?? 'Codex Warning',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AleraTokens.space2),
                Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: tone),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CodexMcpStatusCell extends StatelessWidget {
  const _CodexMcpStatusCell({required this.cell});

  final CodexTimelineCell cell;

  @override
  Widget build(BuildContext context) {
    final status = cell.subtitle?.trim().isNotEmpty == true
        ? cell.subtitle!.trim()
        : cell.metadata['status']?.toString().trim() ?? 'starting';
    final tone = _statusColor(cell.status);
    final details = cell.detailsText?.trim() ?? '';
    return Container(
      key: ValueKey<String>('codex-mcp-status-${cell.id}'),
      margin: const EdgeInsets.only(bottom: AleraTokens.space6),
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space8,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(AleraIcons.host, size: AleraTokens.iconMd, color: tone),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  cell.title ?? 'MCP Server',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AleraTokens.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (details.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AleraTokens.space2),
                  Text(
                    details,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          if (cell.isStreaming)
            _CodexShimmerText(
              key: const ValueKey<String>('codex-mcp-loading-indicator'),
              text: _codexStatusLabel(status),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: tone),
            )
          else ...<Widget>[
            Icon(
              cell.status == CodexTimelineStatus.failed
                  ? AleraIcons.error
                  : AleraIcons.success,
              size: AleraTokens.iconSm,
              color: tone,
            ),
            const SizedBox(width: AleraTokens.space4),
            Text(
              _codexStatusLabel(status),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: tone),
            ),
          ],
        ],
      ),
    );
  }
}

String _codexStatusLabel(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) return 'Ready';
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}
