part of 'codex_chat_surface.dart';

class _CodexExploringCluster extends StatefulWidget {
  const _CodexExploringCluster({
    required this.cells,
    required this.workspacePath,
  });

  final List<CodexTimelineCell> cells;
  final String workspacePath;

  @override
  State<_CodexExploringCluster> createState() => _CodexExploringClusterState();
}

class _CodexExploringClusterState extends State<_CodexExploringCluster> {
  bool _collapsed = true;

  @override
  Widget build(BuildContext context) {
    final files = widget.cells.where(
      (cell) => cell.kind == CodexTimelineKind.diff,
    );
    final searches = widget.cells.where(
      (cell) => cell.metadata['itemType']?.toString() == 'webSearch',
    );
    final streaming = widget.cells.any((cell) => cell.isStreaming);
    final label = streaming
        ? 'Exploring'
        : 'Explored ${files.length} Files, ${searches.length} Searches';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        InkWell(
          onTap: () => setState(() => _collapsed = !_collapsed),
          borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space6,
              vertical: AleraTokens.space4,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (streaming)
                  const Padding(
                    padding: EdgeInsets.only(right: AleraTokens.space6),
                    child: SizedBox.square(
                      dimension: AleraTokens.iconXs,
                      child: CircularProgressIndicator(
                        strokeWidth: AleraTokens.strokeHairline,
                      ),
                    ),
                  ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
                const SizedBox(width: AleraTokens.space4),
                Icon(
                  _collapsed ? AleraIcons.chevronRight : AleraIcons.chevronDown,
                  size: AleraTokens.iconMd,
                  color: AleraTokens.foregroundFaint,
                ),
              ],
            ),
          ),
        ),
        if (!_collapsed)
          Padding(
            padding: const EdgeInsets.only(left: AleraTokens.space8),
            child: Column(
              children: <Widget>[
                for (final cell in widget.cells)
                  _CodexCellView(
                    cell: cell,
                    workspacePath: widget.workspacePath,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CodexCellView extends StatelessWidget {
  const _CodexCellView({required this.cell, required this.workspacePath});

  final CodexTimelineCell cell;
  final String workspacePath;

  @override
  Widget build(BuildContext context) => switch (cell.kind) {
    CodexTimelineKind.userMessage => _CodexUserMessage(
      cell: cell,
      workspacePath: workspacePath,
    ),
    CodexTimelineKind.assistantMessage => _CodexAssistantMessage(cell: cell),
    CodexTimelineKind.progressText => _CodexProgressMessage(cell: cell),
    CodexTimelineKind.reasoning => _CodexReasoningCell(cell: cell),
    CodexTimelineKind.toolCall ||
    CodexTimelineKind.command ||
    CodexTimelineKind.diff => _CodexToolCell(cell: cell),
    CodexTimelineKind.subAgent => _CodexSubAgentCell(cell: cell),
    CodexTimelineKind.plan => _CodexPlanCell(cell: cell),
    CodexTimelineKind.systemNotice => _CodexSystemNotice(cell: cell),
    CodexTimelineKind.questionAnswer => _CodexQuestionAnswerCell(cell: cell),
    CodexTimelineKind.turnSeparator => const SizedBox.shrink(),
  };
}

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
  Widget build(BuildContext context) => Center(
    child: Wrap(
      spacing: AleraTokens.space8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        const Text('Implement This Plan?'),
        FilledButton(
          onPressed: () => unawaited(onImplement()),
          child: const Text('Implement Plan'),
        ),
        TextButton(
          onPressed: () => unawaited(onDecline()),
          child: const Text('Decline'),
        ),
        TextButton(
          onPressed: () => unawaited(_refine(context)),
          child: const Text('Refine Plan'),
        ),
      ],
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
