part of 'codex_chat_surface.dart';

class _CodexReasoningCell extends StatefulWidget {
  const _CodexReasoningCell({required this.cell});

  final CodexTimelineCell cell;

  @override
  State<_CodexReasoningCell> createState() => _CodexReasoningCellState();
}

class _CodexReasoningCellState extends State<_CodexReasoningCell> {
  bool _collapsed = true;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final text =
        widget.cell.renderedMarkdownText ?? widget.cell.markdownText ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: InkWell(
            onTap: text.trim().isEmpty
                ? null
                : () => setState(() => _collapsed = !_collapsed),
            borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space6,
                vertical: AleraTokens.space4,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    AleraIcons.ai,
                    size: AleraTokens.iconSm,
                    color: AleraTokens.foregroundMuted,
                  ),
                  const SizedBox(width: AleraTokens.space6),
                  Text(
                    widget.cell.title ?? 'Thinking',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                  if (text.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(width: AleraTokens.space4),
                    AnimatedOpacity(
                      opacity: _hovered ? 1 : 0,
                      duration: AleraTokens.durationFast,
                      child: Icon(
                        _collapsed
                            ? AleraIcons.chevronRight
                            : AleraIcons.chevronDown,
                        size: AleraTokens.iconMd,
                        color: AleraTokens.foregroundFaint,
                      ),
                    ),
                  ],
                  if (widget.cell.isStreaming) ...<Widget>[
                    const SizedBox(width: AleraTokens.space6),
                    const SizedBox.square(
                      dimension: AleraTokens.iconXs,
                      child: CircularProgressIndicator(
                        strokeWidth: AleraTokens.strokeHairline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (!_collapsed && text.trim().isNotEmpty)
          Container(
            margin: const EdgeInsets.only(
              left: AleraTokens.space8,
              top: AleraTokens.space4,
            ),
            padding: const EdgeInsets.only(left: AleraTokens.space8),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: AleraTokens.borderSubtle,
                  width: AleraTokens.strokeSm,
                ),
              ),
            ),
            child: DefaultTextStyle.merge(
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
              child: _CodexMarkdownText(text: text),
            ),
          ),
      ],
    );
  }
}

class _CodexToolCell extends StatefulWidget {
  const _CodexToolCell({required this.cell});

  final CodexTimelineCell cell;

  @override
  State<_CodexToolCell> createState() => _CodexToolCellState();
}

class _CodexToolCellState extends State<_CodexToolCell> {
  bool _collapsed = true;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cell = widget.cell;
    final details = cell.detailsText ?? cell.markdownText ?? '';
    final label = cell.subtitle?.trim().isNotEmpty == true
        ? '${cell.title ?? _toolFallback(cell)} · ${cell.subtitle}'
        : cell.title ?? _toolFallback(cell);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: InkWell(
            onTap: details.trim().isEmpty
                ? null
                : () => setState(() => _collapsed = !_collapsed),
            borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space6,
                vertical: AleraTokens.space4,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: AleraTokens.codexStatusDotSize,
                    height: AleraTokens.codexStatusDotSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _statusColor(cell.status),
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                  ),
                  if (details.trim().isNotEmpty) ...<Widget>[
                    const SizedBox(width: AleraTokens.space4),
                    AnimatedOpacity(
                      opacity: _hovered ? 1 : 0,
                      duration: AleraTokens.durationFast,
                      child: Icon(
                        _collapsed
                            ? AleraIcons.chevronRight
                            : AleraIcons.chevronDown,
                        size: AleraTokens.iconMd,
                        color: AleraTokens.foregroundFaint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (!_collapsed && details.trim().isNotEmpty)
          Container(
            margin: const EdgeInsets.only(
              left: AleraTokens.space8,
              top: AleraTokens.space4,
            ),
            padding: const EdgeInsets.all(AleraTokens.space8),
            decoration: BoxDecoration(
              color: AleraTokens.surface,
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
              border: Border.all(color: AleraTokens.borderSubtle),
            ),
            child: _CodexToolDetails(cell: cell),
          ),
      ],
    );
  }
}

class _CodexSubAgentCell extends StatefulWidget {
  const _CodexSubAgentCell({required this.cell});

  final CodexTimelineCell cell;

  @override
  State<_CodexSubAgentCell> createState() => _CodexSubAgentCellState();
}

class _CodexSubAgentCellState extends State<_CodexSubAgentCell> {
  bool _collapsed = true;

  @override
  Widget build(BuildContext context) {
    final text =
        widget.cell.renderedMarkdownText ?? widget.cell.markdownText ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          onTap: () => setState(() => _collapsed = !_collapsed),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(AleraIcons.agent, size: AleraTokens.iconSm),
                const SizedBox(width: AleraTokens.space6),
                Text(widget.cell.title ?? 'Sub-Agent'),
                const SizedBox(width: AleraTokens.space4),
                Icon(
                  _collapsed ? AleraIcons.chevronRight : AleraIcons.chevronDown,
                  size: AleraTokens.iconMd,
                ),
              ],
            ),
          ),
        ),
        if (!_collapsed && text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: AleraTokens.space16),
            child: _CodexMarkdownText(text: text),
          ),
      ],
    );
  }
}

class _CodexPlanCell extends StatefulWidget {
  const _CodexPlanCell({required this.cell});

  final CodexTimelineCell cell;

  @override
  State<_CodexPlanCell> createState() => _CodexPlanCellState();
}

class _CodexPlanCellState extends State<_CodexPlanCell> {
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    final raw = widget.cell.markdownText ?? '';
    final text = widget.cell.renderedMarkdownText ?? raw;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _collapsed = !_collapsed),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space12,
                vertical: AleraTokens.space8,
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AleraTokens.space6,
                      vertical: AleraTokens.space2,
                    ),
                    decoration: BoxDecoration(
                      color: AleraTokens.surfaceElevated,
                      borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                    ),
                    child: const Text('Plan'),
                  ),
                  const Spacer(),
                  AleraIconButton(
                    tooltip: 'Copy Plan',
                    icon: AleraIcons.copy,
                    onPressed: () =>
                        _copyCodexText(context, raw, 'Plan copied'),
                  ),
                  Icon(
                    _collapsed
                        ? AleraIcons.chevronRight
                        : AleraIcons.chevronDown,
                    size: AleraTokens.iconMd,
                  ),
                ],
              ),
            ),
          ),
          if (!_collapsed && text.trim().isNotEmpty) ...<Widget>[
            const Divider(height: AleraTokens.dividerExtent),
            Padding(
              padding: const EdgeInsets.all(AleraTokens.space12),
              child: _CodexMarkdownText(text: text),
            ),
            const Divider(height: AleraTokens.dividerExtent),
            TextButton.icon(
              onPressed: () => setState(() => _collapsed = true),
              icon: const Icon(AleraIcons.chevronUp, size: AleraTokens.iconMd),
              label: const Text('Collapse Plan'),
            ),
          ],
        ],
      ),
    );
  }
}

class _CodexQuestionAnswerCell extends StatefulWidget {
  const _CodexQuestionAnswerCell({required this.cell});

  final CodexTimelineCell cell;

  @override
  State<_CodexQuestionAnswerCell> createState() =>
      _CodexQuestionAnswerCellState();
}

class _CodexQuestionAnswerCellState extends State<_CodexQuestionAnswerCell> {
  bool _collapsed = true;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      TextButton.icon(
        onPressed: () => setState(() => _collapsed = !_collapsed),
        icon: Icon(
          _collapsed ? AleraIcons.chevronRight : AleraIcons.chevronDown,
          size: AleraTokens.iconMd,
        ),
        label: const Text('Answered Codex'),
      ),
      if (!_collapsed)
        Padding(
          padding: const EdgeInsets.only(left: AleraTokens.space12),
          child: _CodexMarkdownText(
            text:
                widget.cell.renderedMarkdownText ??
                widget.cell.markdownText ??
                '',
          ),
        ),
    ],
  );
}

class _CodexSystemNotice extends StatelessWidget {
  const _CodexSystemNotice({required this.cell});

  final CodexTimelineCell cell;

  @override
  Widget build(BuildContext context) => Text(
    cell.markdownText ?? cell.title ?? 'Codex Event',
    style: Theme.of(context).textTheme.bodySmall?.copyWith(
      color: cell.status == CodexTimelineStatus.failed
          ? AleraTokens.error
          : AleraTokens.foregroundFaint,
    ),
  );
}

Color _statusColor(CodexTimelineStatus status) => switch (status) {
  CodexTimelineStatus.completed => AleraTokens.success,
  CodexTimelineStatus.failed => AleraTokens.error,
  CodexTimelineStatus.declined => AleraTokens.warning,
  CodexTimelineStatus.inProgress => AleraTokens.info,
  CodexTimelineStatus.info => AleraTokens.foregroundFaint,
};

String _toolFallback(CodexTimelineCell cell) => switch (cell.kind) {
  CodexTimelineKind.command => 'Ran Command',
  CodexTimelineKind.diff => 'Changed Files',
  _ => 'Used Tool',
};
