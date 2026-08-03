part of 'codex_chat_surface.dart';

class _CodexExploringCluster extends StatefulWidget {
  const _CodexExploringCluster({required this.cells});

  final List<CodexTimelineCell> cells;

  @override
  State<_CodexExploringCluster> createState() => _CodexExploringClusterState();
}

class _CodexExploringClusterState extends State<_CodexExploringCluster> {
  bool _collapsed = true;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AleraTokens.surface,
      border: Border.all(color: AleraTokens.borderSubtle),
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ListTile(
          dense: true,
          title: Text('Exploring (${widget.cells.length})'),
          trailing: AleraIconButton(
            tooltip: _collapsed ? 'Expand Exploring' : 'Collapse Exploring',
            icon: _collapsed ? AleraIcons.chevronDown : AleraIcons.chevronUp,
            onPressed: () => setState(() => _collapsed = !_collapsed),
          ),
        ),
        if (!_collapsed)
          for (final cell in widget.cells) _CodexCellView(cell: cell),
      ],
    ),
  );
}

class _CodexCellView extends StatefulWidget {
  const _CodexCellView({required this.cell});

  final CodexTimelineCell cell;

  @override
  State<_CodexCellView> createState() => _CodexCellViewState();
}

class _CodexCellViewState extends State<_CodexCellView> {
  late bool _collapsed =
      widget.cell.isCollapsed || _defaultCollapsed(widget.cell);
  bool _hovered = false;

  bool get _canCollapse => switch (widget.cell.kind) {
    CodexTimelineKind.reasoning ||
    CodexTimelineKind.toolCall ||
    CodexTimelineKind.command ||
    CodexTimelineKind.diff ||
    CodexTimelineKind.subAgent ||
    CodexTimelineKind.plan ||
    CodexTimelineKind.questionAnswer => true,
    _ => false,
  };

  @override
  void didUpdateWidget(covariant _CodexCellView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cell.id != widget.cell.id) {
      _collapsed = widget.cell.isCollapsed || _defaultCollapsed(widget.cell);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cell = widget.cell;
    final text = _safeMarkdown(
      cell.renderedMarkdownText ?? cell.markdownText ?? '',
    );
    final raw = cell.markdownText ?? cell.detailsText ?? cell.title ?? '';
    if (cell.kind == CodexTimelineKind.turnSeparator) {
      return const SizedBox.shrink();
    }
    if (cell.kind == CodexTimelineKind.userMessage) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AleraTokens.chatBubbleMaxWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: AleraTokens.space8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AleraTokens.surfaceVariant,
                borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AleraTokens.space12),
                child: _CodexMarkdownText(text: text.isEmpty ? raw : text),
              ),
            ),
          ),
        ),
      );
    }
    final isAssistant =
        cell.kind == CodexTimelineKind.assistantMessage ||
        cell.kind == CodexTimelineKind.progressText;
    final color = _codexCellColor(cell);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: AleraTokens.space12),
        child: DecoratedBox(
          decoration: isAssistant
              ? const BoxDecoration()
              : BoxDecoration(
                  color: AleraTokens.surface,
                  border: Border.all(color: AleraTokens.borderSubtle),
                  borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                ),
          child: Padding(
            padding: isAssistant
                ? EdgeInsets.zero
                : const EdgeInsets.all(AleraTokens.space12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        _codexCellLabel(cell),
                        style: Theme.of(
                          context,
                        ).textTheme.labelSmall?.copyWith(color: color),
                      ),
                    ),
                    if (cell.isStreaming)
                      const Padding(
                        padding: EdgeInsets.only(right: AleraTokens.space8),
                        child: SizedBox(
                          width: AleraTokens.iconSm,
                          height: AleraTokens.iconSm,
                          child: CircularProgressIndicator(
                            strokeWidth: AleraTokens.strokeSm,
                          ),
                        ),
                      ),
                    if (_canCollapse)
                      AleraIconButton(
                        tooltip: _collapsed ? 'Expand Item' : 'Collapse Item',
                        icon: _collapsed
                            ? AleraIcons.chevronDown
                            : AleraIcons.chevronUp,
                        onPressed: () =>
                            setState(() => _collapsed = !_collapsed),
                      ),
                    if (_hovered || !kIsWeb)
                      AleraIconButton(
                        tooltip: 'Copy',
                        icon: AleraIcons.copy,
                        onPressed: raw.isEmpty
                            ? null
                            : () => unawaited(
                                Clipboard.setData(ClipboardData(text: raw)),
                              ),
                      ),
                  ],
                ),
                if (!_collapsed) ...<Widget>[
                  if (cell.subtitle case final String subtitle
                      when subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AleraTokens.space4),
                      child: Text(subtitle, style: AleraTokens.monoStyle),
                    ),
                  if (text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AleraTokens.space8),
                      child: _CodexMarkdownText(text: text),
                    ),
                  if (cell.detailsText case final String details
                      when details.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AleraTokens.space8),
                      child: SelectableText(
                        details,
                        style: AleraTokens.monoStyle,
                      ),
                    ),
                  if (cell.status == CodexTimelineStatus.failed)
                    Padding(
                      padding: const EdgeInsets.only(top: AleraTokens.space8),
                      child: Text(
                        'Codex could not complete this item.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AleraTokens.error,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CodexMarkdownText extends StatelessWidget {
  const _CodexMarkdownText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: Theme.of(context).textTheme.bodyMedium,
    child: GptMarkdown(text),
  );
}

bool _defaultCollapsed(CodexTimelineCell cell) => switch (cell.kind) {
  CodexTimelineKind.reasoning ||
  CodexTimelineKind.toolCall ||
  CodexTimelineKind.command ||
  CodexTimelineKind.diff ||
  CodexTimelineKind.subAgent ||
  CodexTimelineKind.questionAnswer ||
  CodexTimelineKind.plan => true,
  _ => false,
};

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
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
      child: Row(
        children: <Widget>[
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
            child: Text(
              expanded ? '$label - Hide Details' : '$label - Show Details',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    ),
  );
}

String _workedFor(List<CodexTimelineCell> cells) {
  if (cells.isEmpty) return 'Worked';
  final started = cells
      .map((cell) => cell.createdAt)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  final finished = cells
      .map((cell) => cell.updatedAt)
      .reduce((a, b) => a.isAfter(b) ? a : b);
  final seconds = finished.difference(started).inSeconds;
  if (seconds < 60) return 'Worked for ${seconds}s';
  return 'Worked for ${seconds ~/ 60}m ${seconds % 60}s';
}

List<List<CodexTimelineCell>> _secondaryRows(List<CodexTimelineCell> cells) {
  final rows = <List<CodexTimelineCell>>[];
  for (final cell in cells) {
    final exploratory =
        cell.kind == CodexTimelineKind.command ||
        cell.kind == CodexTimelineKind.toolCall ||
        cell.kind == CodexTimelineKind.diff;
    if (exploratory && rows.isNotEmpty) {
      final previous = rows.last;
      if (previous.isNotEmpty &&
          (previous.last.kind == CodexTimelineKind.command ||
              previous.last.kind == CodexTimelineKind.toolCall ||
              previous.last.kind == CodexTimelineKind.diff)) {
        previous.add(cell);
        continue;
      }
    }
    rows.add(<CodexTimelineCell>[cell]);
  }
  return rows;
}

Color _codexCellColor(CodexTimelineCell cell) => switch (cell.kind) {
  CodexTimelineKind.reasoning => AleraTokens.foregroundMuted,
  CodexTimelineKind.toolCall ||
  CodexTimelineKind.command => AleraTokens.warning,
  CodexTimelineKind.diff => AleraTokens.success,
  CodexTimelineKind.plan => AleraTokens.info,
  CodexTimelineKind.subAgent => AleraTokens.accent,
  CodexTimelineKind.systemNotice => AleraTokens.error,
  _ => AleraTokens.foreground,
};

String _codexCellLabel(CodexTimelineCell cell) => switch (cell.kind) {
  CodexTimelineKind.assistantMessage => 'Codex',
  CodexTimelineKind.progressText => 'Progress',
  CodexTimelineKind.reasoning => 'Reasoning',
  CodexTimelineKind.toolCall => cell.title ?? 'Tool Call',
  CodexTimelineKind.command => cell.title ?? 'Command',
  CodexTimelineKind.diff => cell.title ?? 'File Changes',
  CodexTimelineKind.subAgent => cell.title ?? 'Sub-Agent',
  CodexTimelineKind.plan => 'Plan',
  CodexTimelineKind.questionAnswer => 'Question Answer',
  CodexTimelineKind.systemNotice => cell.title ?? 'Notice',
  _ => cell.title ?? 'Codex Activity',
};

class _CodexRawEvent extends StatelessWidget {
  const _CodexRawEvent({required this.event});

  final CodexTimelineEvent event;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AleraTokens.space4),
    child: SelectableText(
      '${event.method}: ${event.raw}',
      style: AleraTokens.monoStyle,
    ),
  );
}

class _CodexPlanPrompt extends StatelessWidget {
  const _CodexPlanPrompt({
    required this.onImplement,
    required this.onDecline,
    required this.onRefine,
  });

  final Future<void> Function() onImplement;
  final Future<void> Function() onDecline;
  final Future<void> Function(String refinement) onRefine;

  @override
  Widget build(BuildContext context) => Card(
    color: AleraTokens.surfaceElevated,
    child: Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AleraTokens.space8,
        runSpacing: AleraTokens.space8,
        children: <Widget>[
          const Text('Implement this plan?'),
          FilledButton(
            onPressed: () => unawaited(onImplement()),
            child: const Text('Implement Plan'),
          ),
          TextButton(
            onPressed: () => unawaited(onDecline()),
            child: const Text('Decline'),
          ),
          OutlinedButton(
            onPressed: () => unawaited(_refine(context)),
            child: const Text('Refine Plan'),
          ),
        ],
      ),
    ),
  );

  Future<void> _refine(BuildContext context) async {
    final input = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Refine Plan'),
        content: TextField(
          controller: input,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Tell Codex what to change.',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(input.text),
            child: const Text('Send Refinement'),
          ),
        ],
      ),
    );
    input.dispose();
    if (value != null && value.trim().isNotEmpty) await onRefine(value);
  }
}
