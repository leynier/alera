part of 'mobile_codex_chat_screen.dart';

class _MobileTimelineRow extends StatelessWidget {
  const _MobileTimelineRow({
    required this.row,
    required this.onOpenPlan,
    required this.activityExpanded,
    required this.onToggleActivity,
    required this.turnExpanded,
    required this.onToggleTurn,
    required this.showTurnActivity,
    required this.planPreviewInitiallyOverflowing,
    required this.onPlanPreviewOverflowChanged,
  });

  final MobileCodexPresentationRow row;
  final ValueChanged<MobileCodexTimelineCell> onOpenPlan;
  final bool activityExpanded;
  final VoidCallback onToggleActivity;
  final bool turnExpanded;
  final VoidCallback onToggleTurn;
  final bool showTurnActivity;
  final bool planPreviewInitiallyOverflowing;
  final void Function(String planId, bool overflowing)
  onPlanPreviewOverflowChanged;

  @override
  Widget build(BuildContext context) {
    if (!showTurnActivity) return const SizedBox.shrink();
    return switch (row.kind) {
      MobileCodexPresentationKind.cell => _MobileTimelineCell(
        cell: row.cell!,
        isPreviousPlan: row.isPreviousPlan,
        onOpenPlan: onOpenPlan,
        planPreviewInitiallyOverflowing: planPreviewInitiallyOverflowing,
        onPlanPreviewOverflowChanged: onPlanPreviewOverflowChanged,
        turnExpanded: turnExpanded,
        onToggleTurn: onToggleTurn,
        turnActivityCount: row.turnActivityCount,
      ),
      MobileCodexPresentationKind.activity => _MobileActivityGroup(
        cells: row.activityCells,
        expanded: activityExpanded,
        onToggle: onToggleActivity,
      ),
      MobileCodexPresentationKind.working => _MobileWorkingRow(
        startedAt: row.startedAt,
        expanded: turnExpanded,
        canToggle: row.turnActivityCount > 0,
        onToggle: onToggleTurn,
      ),
    };
  }
}

class _MobileTimelineCell extends StatefulWidget {
  const _MobileTimelineCell({
    required this.cell,
    required this.onOpenPlan,
    required this.planPreviewInitiallyOverflowing,
    required this.onPlanPreviewOverflowChanged,
    required this.turnExpanded,
    required this.onToggleTurn,
    required this.turnActivityCount,
    this.isPreviousPlan = false,
  });

  final MobileCodexTimelineCell cell;
  final bool isPreviousPlan;
  final ValueChanged<MobileCodexTimelineCell> onOpenPlan;
  final bool planPreviewInitiallyOverflowing;
  final void Function(String planId, bool overflowing)
  onPlanPreviewOverflowChanged;
  final bool turnExpanded;
  final VoidCallback onToggleTurn;
  final int turnActivityCount;

  @override
  State<_MobileTimelineCell> createState() => _MobileTimelineCellState();
}

class _MobileTimelineCellState extends State<_MobileTimelineCell> {
  late bool _collapsed =
      widget.cell.isCollapsed || _mobileDefaultCollapsed(widget.cell);
  bool _raw = false;

  @override
  void didUpdateWidget(covariant _MobileTimelineCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cell.id != widget.cell.id) {
      _collapsed =
          widget.cell.isCollapsed || _mobileDefaultCollapsed(widget.cell);
      _raw = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cell = widget.cell;
    if (cell.kind == 'turnSeparator') {
      return _MobileWorkedRow(
        cell: cell,
        expanded: widget.turnExpanded,
        canToggle: widget.turnActivityCount > 1,
        onToggle: widget.onToggleTurn,
      );
    }
    if (cell.kind == 'plan') {
      return _MobilePlanCard(
        cell: cell,
        previous: widget.isPreviousPlan,
        onOpen: () => widget.onOpenPlan(cell),
        initiallyOverflowing: widget.planPreviewInitiallyOverflowing,
        onOverflowChanged: (overflowing) =>
            widget.onPlanPreviewOverflowChanged(cell.id, overflowing),
      );
    }
    if (cell.isUser || cell.isAssistant) return _message(context, cell);
    if (_isMcpStatus(cell)) return _MobileMcpStatus(cell: cell);
    if (_isWarning(cell)) return _MobileWarningNotice(cell: cell);
    if (cell.kind == 'progressText') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AleraTokens.space6),
        child: _MobileCodexMarkdown(text: cell.displayText),
      );
    }
    final collapseable = cell.kind != 'command';
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space8),
      child: Material(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
          onTap: collapseable
              ? () => setState(() => _collapsed = !_collapsed)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(AleraTokens.space12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      _mobileCellIcon(cell),
                      size: AleraTokens.space16,
                      color: _mobileCellColor(cell),
                    ),
                    const SizedBox(width: AleraTokens.space8),
                    Expanded(
                      child: cell.isStreaming
                          ? _MobileCodexShimmerText(
                              text: _mobileCellLabel(cell),
                              style: Theme.of(context).textTheme.labelMedium,
                            )
                          : Text(
                              _mobileCellLabel(cell),
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                    ),
                    if (collapseable)
                      Icon(
                        _collapsed ? Icons.chevron_right : Icons.expand_more,
                        size: AleraTokens.space16,
                      ),
                  ],
                ),
                if (!_collapsed) ...<Widget>[
                  if (cell.subtitle?.isNotEmpty == true) ...<Widget>[
                    const SizedBox(height: AleraTokens.space6),
                    Text(cell.subtitle!, style: AleraTokens.monoStyle),
                  ],
                  const SizedBox(height: AleraTokens.space8),
                  _MobileCodexMarkdown(text: cell.displayText),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _message(BuildContext context, MobileCodexTimelineCell cell) {
    final raw = cell.markdownText ?? cell.displayText;
    final body = _raw
        ? SelectableText(raw)
        : _MobileCodexMarkdown(text: cell.displayText);
    final actions = _MobileMessageActions(
      cell: cell,
      raw: _raw,
      onToggleRaw: () => setState(() => _raw = !_raw),
    );
    if (cell.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AleraTokens.chatBubbleMaxWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: AleraTokens.space12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                _MobileMessageAttachments(cell: cell),
                if (raw.trim().isNotEmpty)
                  Material(
                    color: AleraTokens.surfaceVariant,
                    borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                    child: Padding(
                      padding: const EdgeInsets.all(AleraTokens.space12),
                      child: body,
                    ),
                  ),
                const SizedBox(height: AleraTokens.space8),
                actions,
              ],
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          body,
          if (cell.isStreaming)
            Padding(
              padding: const EdgeInsets.only(top: AleraTokens.space6),
              child: _MobileCodexShimmerText(
                text: 'Streaming',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else ...<Widget>[const SizedBox(height: AleraTokens.space8), actions],
        ],
      ),
    );
  }
}

class _MobileMessageActions extends StatelessWidget {
  const _MobileMessageActions({
    required this.cell,
    required this.raw,
    required this.onToggleRaw,
  });

  final MobileCodexTimelineCell cell;
  final bool raw;
  final VoidCallback onToggleRaw;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      IconButton(
        tooltip: 'Copy Message',
        visualDensity: VisualDensity.compact,
        onPressed: () => unawaited(
          Clipboard.setData(
            ClipboardData(text: cell.markdownText ?? cell.displayText),
          ),
        ),
        icon: const Icon(Icons.copy_outlined, size: AleraTokens.space16),
      ),
      IconButton(
        tooltip: raw ? 'Show Markdown' : 'Show Source',
        visualDensity: VisualDensity.compact,
        onPressed: onToggleRaw,
        icon: const Icon(Icons.code, size: AleraTokens.space16),
      ),
      if (cell.createdAt != null)
        Text(
          _mobileTimestamp(cell.createdAt!),
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AleraTokens.foregroundFaint),
        ),
    ],
  );
}

class _MobileMessageAttachments extends StatelessWidget {
  const _MobileMessageAttachments({required this.cell});

  final MobileCodexTimelineCell cell;

  @override
  Widget build(BuildContext context) {
    final raw = cell.metadata['attachments'];
    if (raw is! List || raw.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space6),
      child: Wrap(
        spacing: AleraTokens.space6,
        runSpacing: AleraTokens.space6,
        alignment: WrapAlignment.end,
        children: <Widget>[
          for (final value in raw)
            if (value is Map)
              ActionChip(
                avatar: Icon(
                  value['isDirectory'] == true
                      ? Icons.folder_outlined
                      : _mobileFileIcon(value['path']?.toString() ?? ''),
                  size: AleraTokens.space16,
                ),
                label: Text(
                  value['displayName']?.toString() ??
                      value['name']?.toString() ??
                      _mobileBaseName(value['path']?.toString() ?? ''),
                ),
                onPressed: value['isDirectory'] == true
                    ? null
                    : () => unawaited(
                        _openMobileCodexPath(
                          context,
                          value['path']?.toString() ?? '',
                          displayName:
                              value['displayName']?.toString() ??
                              value['name']?.toString(),
                        ),
                      ),
              ),
        ],
      ),
    );
  }
}

bool _mobileDefaultCollapsed(MobileCodexTimelineCell cell) =>
    switch (cell.kind) {
      'toolCall' || 'diff' || 'subAgent' || 'questionAnswer' => true,
      _ => false,
    };

String _mobileCellLabel(MobileCodexTimelineCell cell) {
  if (cell.kind == 'questionAnswer') {
    final count = cell.metadata['questionCount'];
    return 'Asked ${count is int ? count : 1} Questions';
  }
  if (cell.kind == 'command') return cell.title ?? 'Ran Command';
  if (cell.kind == 'toolCall') return cell.title ?? 'Tool Call';
  if (cell.kind == 'diff') return cell.title ?? 'Edited Files';
  if (cell.kind == 'subAgent') return cell.title ?? 'Sub-Agent';
  return cell.title ?? 'Codex Activity';
}

Color _mobileCellColor(MobileCodexTimelineCell cell) => switch (cell.status) {
  'failed' => AleraTokens.error,
  'warning' => AleraTokens.warning,
  _ => AleraTokens.foregroundMuted,
};

IconData _mobileCellIcon(MobileCodexTimelineCell cell) => switch (cell.kind) {
  'questionAnswer' => Icons.help_outline,
  'diff' => Icons.edit_outlined,
  'command' => Icons.terminal,
  'subAgent' => Icons.account_tree_outlined,
  'toolCall' when _mobileActivityKind(cell) == _MobileActivityKind.viewImage =>
    AleraIcons.viewImage,
  _ => Icons.info_outline,
};

String _mobileTimestamp(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
}
