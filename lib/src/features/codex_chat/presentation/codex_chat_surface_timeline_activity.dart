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
          cursor: text.trim().isEmpty
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: InkWell(
            onTap: text.trim().isEmpty
                ? null
                : () => setState(() => _collapsed = !_collapsed),
            mouseCursor: text.trim().isEmpty
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    AleraIcons.ai,
                    size: AleraTokens.iconSm,
                    color: AleraTokens.foregroundMuted,
                  ),
                  const SizedBox(width: AleraTokens.space6),
                  if (widget.cell.isStreaming)
                    _CodexShimmerText(
                      text: widget.cell.title ?? 'Thinking',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    )
                  else
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
    if (cell.metadata['itemType'] == 'mcpServerStartup') {
      return _CodexMcpStatusCell(cell: cell);
    }
    if (_isContextCompaction(cell)) {
      return _CodexContextCompactionCell(cell: cell);
    }
    final hasDetails = _codexWorkedActionHasDetails(cell);
    final label = cell.subtitle?.trim().isNotEmpty == true
        ? '${cell.title ?? _toolFallback(cell)} · ${cell.subtitle}'
        : cell.title ?? _toolFallback(cell);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        MouseRegion(
          cursor: !hasDetails
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: InkWell(
            onTap: !hasDetails
                ? null
                : () => setState(() => _collapsed = !_collapsed),
            mouseCursor: !hasDetails
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
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
                  if (hasDetails) ...<Widget>[
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
        if (!_collapsed && hasDetails)
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

class _CodexContextCompactionCell extends StatelessWidget {
  const _CodexContextCompactionCell({required this.cell});

  final CodexTimelineCell cell;

  @override
  Widget build(BuildContext context) {
    final active =
        cell.isStreaming || cell.status == CodexTimelineStatus.inProgress;
    final label = switch (cell.status) {
      CodexTimelineStatus.failed => 'Compaction failed',
      _ when active => 'Compacting',
      _ => 'Compacted',
    };
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: cell.status == CodexTimelineStatus.failed
          ? AleraTokens.error
          : AleraTokens.foregroundMuted,
    );
    return Padding(
      key: ValueKey<String>('codex-context-compaction-${cell.id}'),
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space6,
        vertical: AleraTokens.space4,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            AleraIcons.contextCompact,
            size: AleraTokens.iconSm,
            color: cell.status == CodexTimelineStatus.failed
                ? AleraTokens.error
                : AleraTokens.foregroundMuted,
          ),
          const SizedBox(width: AleraTokens.space6),
          if (active)
            _CodexShimmerText(text: label, style: style)
          else
            Text(label, style: style),
        ],
      ),
    );
  }
}

bool _isContextCompaction(CodexTimelineCell cell) => cell.metadata['itemType']
    .toString()
    .toLowerCase()
    .contains('contextcompaction');

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
          mouseCursor: SystemMouseCursors.click,
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
  Widget build(BuildContext context) {
    final answers = _questionAnswers(widget.cell);
    final storedCount = widget.cell.metadata['questionCount'];
    final count = storedCount is num && storedCount.toInt() >= answers.length
        ? storedCount.toInt()
        : answers.length;
    final label = 'Asked $count ${count == 1 ? 'question' : 'questions'}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: InkWell(
              key: const ValueKey<String>('codex-question-answer-header'),
              onTap: () => setState(() => _collapsed = !_collapsed),
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AleraTokens.space4,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      AleraIcons.question,
                      size: AleraTokens.iconLg,
                      color: AleraTokens.foregroundMuted,
                    ),
                    const SizedBox(width: AleraTokens.space8),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                    const SizedBox(width: AleraTokens.space6),
                    Icon(
                      _collapsed
                          ? AleraIcons.chevronRight
                          : AleraIcons.chevronDown,
                      size: AleraTokens.iconMd,
                      color: AleraTokens.foregroundMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!_collapsed)
            Padding(
              key: const ValueKey<String>('codex-question-answer-details'),
              padding: const EdgeInsets.only(top: AleraTokens.space12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final answer in answers)
                    Padding(
                      padding: const EdgeInsets.only(
                        bottom: AleraTokens.space16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            answer.question,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AleraTokens.foregroundMuted),
                          ),
                          const SizedBox(height: AleraTokens.space6),
                          DefaultTextStyle.merge(
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AleraTokens.foregroundFaint),
                            child: _CodexMarkdownText(text: answer.answer),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

List<({String question, String answer})> _questionAnswers(
  CodexTimelineCell cell,
) {
  final values = cell.metadata['questions'];
  final answers = <({String question, String answer})>[];
  if (values is List) {
    for (final value in values) {
      if (value is! Map) continue;
      final question = value['question']?.toString().trim() ?? '';
      final answer = value['answer']?.toString().trim() ?? '';
      if (question.isNotEmpty && answer.isNotEmpty) {
        answers.add((question: question, answer: answer));
      }
    }
  }
  if (answers.isNotEmpty) return answers;
  final fallback = cell.markdownText?.trim() ?? '';
  return <({String question, String answer})>[
    (question: cell.title ?? 'Codex question', answer: fallback),
  ];
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
