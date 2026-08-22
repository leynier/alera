part of 'codex_chat_surface.dart';

class _CodexCellView extends StatelessWidget {
  const _CodexCellView({
    required this.cell,
    required this.workspacePath,
    required this.onOpenAttachment,
  });

  final CodexTimelineCell cell;
  final String workspacePath;
  final Future<void> Function(String path, {required bool isImage})
  onOpenAttachment;

  @override
  Widget build(BuildContext context) => switch (cell.kind) {
    CodexTimelineKind.userMessage => _CodexUserMessage(
      cell: cell,
      workspacePath: workspacePath,
      onOpenAttachment: onOpenAttachment,
    ),
    CodexTimelineKind.assistantMessage => _CodexAssistantMessage(
      cell: cell,
      workspacePath: workspacePath,
    ),
    CodexTimelineKind.progressText => _CodexProgressMessage(cell: cell),
    CodexTimelineKind.reasoning => _CodexReasoningCell(cell: cell),
    CodexTimelineKind.toolCall ||
    CodexTimelineKind.command ||
    CodexTimelineKind.diff => _CodexToolCell(cell: cell),
    CodexTimelineKind.subAgent => _CodexSubAgentCell(cell: cell),
    CodexTimelineKind.plan =>
      cell.metadata['plan'] is List
          ? const SizedBox.shrink()
          : _CodexPlanCell(cell: cell),
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
