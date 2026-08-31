part of 'codex_chat_surface.dart';

class const _CodexCellView({
  required final CodexTimelineCell cell,
  required final String workspacePath,
  required final Future<void> Function(String path, {required bool isImage})
  onOpenAttachment,
}) extends StatelessWidget {
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

class const _CodexRawEvent({required final CodexTimelineEvent event})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AleraTokens.space4),
    child: SelectableText(
      '${event.method}: ${event.raw}',
      style: AleraTokens.monoStyle,
    ),
  );
}
