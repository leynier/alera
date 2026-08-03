part of 'codex_chat_surface.dart';

class _CodexTimeline extends StatelessWidget {
  const _CodexTimeline({
    required this.snapshot,
    required this.showRawLogs,
    required this.timeline,
    required this.onApproval,
    required this.onQuestion,
    required this.onImplementPlan,
  });

  final CodexChatSnapshot snapshot;
  final bool showRawLogs;
  final ScrollController timeline;
  final Future<void> Function(
    CodexPendingRequest request, {
    required bool accepted,
    bool forSession,
  })
  onApproval;
  final Future<void> Function(
    CodexPendingRequest request,
    Map<String, List<String>> answers,
  )
  onQuestion;
  final Future<void> Function() onImplementPlan;

  @override
  Widget build(BuildContext context) {
    final cells = snapshot.timelineCells;
    if (cells.isEmpty && snapshot.pendingRequests.isEmpty && !showRawLogs) {
      return const Center(child: Text('Ask Codex to work on this workspace.'));
    }
    return SelectionArea(
      child: ListView(
        controller: timeline,
        padding: const EdgeInsets.all(AleraTokens.space16),
        children: <Widget>[
          for (final cell in cells) _CodexTimelineCellCard(cell: cell),
          if (showRawLogs)
            for (final event in snapshot.events) _CodexRawEvent(event: event),
          for (final request in snapshot.pendingRequests)
            if (request.isApproval)
              _CodexApprovalCard(request: request, onApproval: onApproval)
            else if (request.isQuestion)
              _CodexQuestionCard(request: request, onQuestion: onQuestion)
            else
              _CodexPendingCard(request: request),
          if (snapshot.hasPlan)
            Align(
              alignment: Alignment.center,
              child: FilledButton(
                onPressed: () => unawaited(onImplementPlan()),
                child: const Text('Implement Plan'),
              ),
            ),
        ],
      ),
    );
  }
}

class _CodexTimelineCellCard extends StatelessWidget {
  const _CodexTimelineCellCard({required this.cell});

  final CodexTimelineCell cell;

  @override
  Widget build(BuildContext context) {
    if (cell.kind == CodexTimelineKind.turnSeparator) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AleraTokens.space8),
        child: Row(
          children: <Widget>[
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space8,
              ),
              child: Text(
                cell.title ?? 'Turn',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            const Expanded(child: Divider()),
          ],
        ),
      );
    }
    final color = switch (cell.kind) {
      CodexTimelineKind.userMessage => AleraTokens.info,
      CodexTimelineKind.reasoning => AleraTokens.foregroundMuted,
      CodexTimelineKind.toolCall ||
      CodexTimelineKind.command => AleraTokens.warning,
      CodexTimelineKind.diff => AleraTokens.success,
      CodexTimelineKind.plan => AleraTokens.info,
      CodexTimelineKind.subAgent => AleraTokens.accent,
      CodexTimelineKind.systemNotice => AleraTokens.error,
      _ => AleraTokens.foreground,
    };
    final text =
        cell.markdownText ?? cell.detailsText ?? cell.title ?? 'Codex activity';
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cell.kind == CodexTimelineKind.userMessage
              ? AleraTokens.surfaceVariant
              : AleraTokens.surface,
          border: Border.all(color: AleraTokens.borderSubtle),
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _cellLabel(cell),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (cell.isStreaming)
                    const Padding(
                      padding: EdgeInsets.only(right: AleraTokens.space8),
                      child: SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                    ),
                  AleraIconButton(
                    tooltip: 'Copy',
                    icon: AleraIcons.copy,
                    onPressed: () =>
                        unawaited(Clipboard.setData(ClipboardData(text: text))),
                  ),
                ],
              ),
              if (cell.subtitle case final String subtitle
                  when subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AleraTokens.space4),
                  child: Text(subtitle, style: AleraTokens.monoStyle),
                ),
              if (cell.markdownText case final String markdown
                  when markdown.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AleraTokens.space8),
                  child:
                      cell.kind == CodexTimelineKind.assistantMessage ||
                          cell.kind == CodexTimelineKind.progressText ||
                          cell.kind == CodexTimelineKind.plan
                      ? GptMarkdown(markdown)
                      : SelectableText(
                          markdown,
                          style: TextStyle(color: color, height: 1.4),
                        ),
                ),
              if (cell.detailsText case final String details
                  when details.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AleraTokens.space8),
                  child: SelectableText(details, style: AleraTokens.monoStyle),
                ),
              if (cell.status == CodexTimelineStatus.failed)
                Padding(
                  padding: const EdgeInsets.only(top: AleraTokens.space8),
                  child: Text(
                    'Codex could not complete this item.',
                    style: TextStyle(color: AleraTokens.error),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CodexRawEvent extends StatelessWidget {
  const _CodexRawEvent({required this.event});

  final CodexTimelineEvent event;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AleraTokens.space4),
    child: SelectableText(
      '${event.method}: ${event.raw}',
      style: AleraTokens.monoStyle.copyWith(fontSize: 11),
    ),
  );
}

String _cellLabel(CodexTimelineCell cell) {
  if (cell.kind == CodexTimelineKind.userMessage) return 'You';
  if (cell.kind == CodexTimelineKind.assistantMessage) return 'Codex';
  if (cell.kind == CodexTimelineKind.progressText) return 'Progress';
  if (cell.kind == CodexTimelineKind.reasoning) return 'Reasoning';
  if (cell.kind == CodexTimelineKind.toolCall) return cell.title ?? 'Tool Call';
  if (cell.kind == CodexTimelineKind.command) return cell.title ?? 'Command';
  if (cell.kind == CodexTimelineKind.diff) return cell.title ?? 'File Changes';
  if (cell.kind == CodexTimelineKind.subAgent) return cell.title ?? 'Sub-Agent';
  if (cell.kind == CodexTimelineKind.plan) return 'Plan';
  if (cell.kind == CodexTimelineKind.systemNotice) {
    return cell.title ?? 'Notice';
  }
  return cell.title ?? 'Codex Activity';
}

class _CodexApprovalCard extends StatelessWidget {
  const _CodexApprovalCard({required this.request, required this.onApproval});

  final CodexPendingRequest request;
  final Future<void> Function(
    CodexPendingRequest request, {
    required bool accepted,
    bool forSession,
  })
  onApproval;

  @override
  Widget build(BuildContext context) => _CodexRequestCard(
    title: request.requestTitle,
    body: request.approvalDescription,
    actions: <Widget>[
      TextButton(
        onPressed: () => unawaited(onApproval(request, accepted: false)),
        child: const Text('Decline'),
      ),
      FilledButton(
        onPressed: () => unawaited(onApproval(request, accepted: true)),
        child: const Text('Approve'),
      ),
      TextButton(
        onPressed: () =>
            unawaited(onApproval(request, accepted: true, forSession: true)),
        child: const Text('Approve For Session'),
      ),
    ],
  );
}

class _CodexQuestionCard extends StatefulWidget {
  const _CodexQuestionCard({required this.request, required this.onQuestion});

  final CodexPendingRequest request;
  final Future<void> Function(
    CodexPendingRequest request,
    Map<String, List<String>> answers,
  )
  onQuestion;

  @override
  State<_CodexQuestionCard> createState() => _CodexQuestionCardState();
}

class _CodexQuestionCardState extends State<_CodexQuestionCard> {
  final Map<String, TextEditingController> _answers =
      <String, TextEditingController>{};
  final Map<String, Set<String>> _selected = <String, Set<String>>{};

  @override
  void dispose() {
    for (final controller in _answers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final questions = widget.request.questions;
    return _CodexRequestCard(
      title: widget.request.requestTitle,
      bodyWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final question in questions) _question(context, question),
        ],
      ),
      actions: <Widget>[
        FilledButton(
          onPressed: () => unawaited(
            widget.onQuestion(widget.request, <String, List<String>>{
              for (final question in questions)
                question.id:
                    question.isOther &&
                        (_answers[question.id]?.text.trim().isNotEmpty ?? false)
                    ? <String>[_answers[question.id]!.text.trim()]
                    : _selected[question.id]
                              ?.toList(growable: false)
                              .isNotEmpty ==
                          true
                    ? _selected[question.id]!.toList(growable: false)
                    : <String>[_answers[question.id]?.text.trim() ?? ''],
            }),
          ),
          child: const Text('Submit Answers'),
        ),
      ],
    );
  }

  Widget _question(BuildContext context, CodexQuestion question) {
    final controller = _answers.putIfAbsent(
      question.id,
      TextEditingController.new,
    );
    final selected = _selected.putIfAbsent(question.id, () => <String>{});
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            question.header ?? question.question,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (question.header != null) Text(question.question),
          if (question.options.isNotEmpty)
            Wrap(
              spacing: AleraTokens.space4,
              runSpacing: AleraTokens.space4,
              children: <Widget>[
                for (final option in question.options)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: selected.contains(option.label),
                    onSelected: (isSelected) => setState(() {
                      if (!question.isMultiSelect) selected.clear();
                      if (isSelected) {
                        selected.add(option.label);
                      } else {
                        selected.remove(option.label);
                      }
                    }),
                  ),
              ],
            ),
          if (question.options.isEmpty || question.isOther)
            TextField(
              controller: controller,
              obscureText: question.isSecret,
              decoration: const InputDecoration(hintText: 'Your Answer'),
            ),
        ],
      ),
    );
  }
}

class _CodexPendingCard extends StatelessWidget {
  const _CodexPendingCard({required this.request});

  final CodexPendingRequest request;

  @override
  Widget build(BuildContext context) => _CodexRequestCard(
    title: request.requestTitle,
    body: request.method,
    actions: const <Widget>[],
  );
}

class _CodexRequestCard extends StatelessWidget {
  const _CodexRequestCard({
    required this.title,
    this.body,
    this.bodyWidget,
    required this.actions,
  });

  final String title;
  final String? body;
  final Widget? bodyWidget;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Card(
    color: AleraTokens.surfaceElevated,
    child: Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          if (body != null) ...<Widget>[
            const SizedBox(height: AleraTokens.space6),
            Text(body!),
          ],
          if (bodyWidget != null) ...<Widget>[
            const SizedBox(height: AleraTokens.space6),
            bodyWidget!,
          ],
          if (actions.isNotEmpty) ...<Widget>[
            const SizedBox(height: AleraTokens.space8),
            Wrap(spacing: AleraTokens.space8, children: actions),
          ],
        ],
      ),
    ),
  );
}
