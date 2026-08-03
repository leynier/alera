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
    Map<String, Object?> answers,
  )
  onQuestion;
  final Future<void> Function() onImplementPlan;

  @override
  Widget build(BuildContext context) {
    if (snapshot.events.isEmpty && snapshot.pendingRequests.isEmpty) {
      return const Center(child: Text('Ask Codex to work on this workspace.'));
    }
    return SelectionArea(
      child: ListView(
        controller: timeline,
        padding: const EdgeInsets.all(AleraTokens.space16),
        children: <Widget>[
          for (final event in snapshot.events)
            if (showRawLogs ||
                event.text.isNotEmpty ||
                event.method.contains('turn/'))
              _CodexEventCard(event: event, showRawLogs: showRawLogs),
          for (final request in snapshot.pendingRequests)
            request.isApproval
                ? _CodexApprovalCard(request: request, onApproval: onApproval)
                : request.isQuestion
                ? _CodexQuestionCard(request: request, onQuestion: onQuestion)
                : _CodexPendingCard(request: request),
          if (snapshot.events.any((event) => event.isPlan))
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

class _CodexEventCard extends StatelessWidget {
  const _CodexEventCard({required this.event, required this.showRawLogs});

  final CodexTimelineEvent event;
  final bool showRawLogs;

  @override
  Widget build(BuildContext context) {
    final color = event.isUser
        ? AleraTokens.info
        : event.isReasoning
        ? AleraTokens.foregroundMuted
        : event.isTool || event.isCommand
        ? AleraTokens.warning
        : AleraTokens.foreground;
    final text = event.text.isEmpty
        ? (event.title ?? event.method)
        : event.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: event.isUser
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
                      _eventLabel(event),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
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
              const SizedBox(height: AleraTokens.space6),
              if (event.isAssistant && !showRawLogs)
                GptMarkdown(text)
              else
                SelectableText(
                  text,
                  style: TextStyle(color: color, height: 1.4),
                ),
              if (showRawLogs) ...<Widget>[
                const SizedBox(height: AleraTokens.space8),
                SelectableText(
                  event.raw.toString(),
                  style: AleraTokens.monoStyle.copyWith(fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _eventLabel(CodexTimelineEvent event) {
  if (event.isUser) return 'You';
  if (event.isAssistant) return 'Codex';
  if (event.isReasoning) return 'Reasoning';
  if (event.isTool) return 'Tool';
  if (event.isCommand) return 'Command';
  if (event.isDiff) return 'Diff';
  if (event.isPlan) return 'Plan';
  if (event.isSubAgent) return 'Sub-Agent';
  return event.method;
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
  Widget build(BuildContext context) {
    return _CodexRequestCard(
      title: 'Codex Needs Approval',
      body:
          request.params['command']?.toString() ??
          request.params['reason']?.toString() ??
          'Codex is requesting permission to continue.',
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
}

class _CodexQuestionCard extends StatefulWidget {
  const _CodexQuestionCard({required this.request, required this.onQuestion});

  final CodexPendingRequest request;
  final Future<void> Function(
    CodexPendingRequest request,
    Map<String, Object?> answers,
  )
  onQuestion;

  @override
  State<_CodexQuestionCard> createState() => _CodexQuestionCardState();
}

class _CodexQuestionCardState extends State<_CodexQuestionCard> {
  late final TextEditingController _answer;

  @override
  void initState() {
    super.initState();
    _answer = TextEditingController();
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _CodexRequestCard(
      title: 'Codex Needs Your Input',
      body:
          widget.request.params['question']?.toString() ??
          'Codex asked a question.',
      actions: <Widget>[
        SizedBox(
          width: 260,
          child: TextField(
            controller: _answer,
            decoration: const InputDecoration(hintText: 'Your answer'),
          ),
        ),
        FilledButton(
          onPressed: () => unawaited(
            widget.onQuestion(widget.request, <String, Object?>{
              'answer': _answer.text,
            }),
          ),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

class _CodexPendingCard extends StatelessWidget {
  const _CodexPendingCard({required this.request});

  final CodexPendingRequest request;

  @override
  Widget build(BuildContext context) {
    return _CodexRequestCard(
      title: 'Codex Request',
      body: request.method,
      actions: const <Widget>[],
    );
  }
}

class _CodexRequestCard extends StatelessWidget {
  const _CodexRequestCard({
    required this.title,
    required this.body,
    required this.actions,
  });

  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AleraTokens.surfaceElevated,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AleraTokens.space6),
            Text(body),
            if (actions.isNotEmpty) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              Wrap(spacing: AleraTokens.space8, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}
