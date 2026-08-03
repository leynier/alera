part of 'codex_chat_surface.dart';

class _CodexPendingCard extends StatelessWidget {
  const _CodexPendingCard({required this.request, required this.onReject});

  final CodexPendingRequest request;
  final Future<void> Function(CodexPendingRequest request) onReject;

  @override
  Widget build(BuildContext context) => _CodexRequestCard(
    title: request.requestTitle,
    body: request.method,
    actions: <Widget>[
      TextButton(
        onPressed: () => unawaited(onReject(request)),
        child: const Text('Reject'),
      ),
    ],
  );
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
          Text(
            widget.request.isBlocking
                ? 'Response required.'
                : 'Response optional.',
          ),
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

class _CodexElicitationCard extends StatefulWidget {
  const _CodexElicitationCard({
    required this.request,
    required this.onElicitation,
  });

  final CodexPendingRequest request;
  final Future<void> Function(
    CodexPendingRequest request, {
    required String action,
    Map<String, Object?> content,
  })
  onElicitation;

  @override
  State<_CodexElicitationCard> createState() => _CodexElicitationCardState();
}

class _CodexElicitationCardState extends State<_CodexElicitationCard> {
  final Map<String, TextEditingController> _fields =
      <String, TextEditingController>{};

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final supported = widget.request.hasSupportedElicitationForm;
    final properties = supported
        ? (widget.request.elicitationSchema['properties'] as Map)
        : const <Object?, Object?>{};
    return _CodexRequestCard(
      title: 'MCP Server Needs Input',
      bodyWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(widget.request.params['message']?.toString() ?? ''),
          if (!supported)
            const Text(
              'This elicitation form is not supported on this client.',
            ),
          for (final entry in properties.entries)
            TextField(
              controller: _fields.putIfAbsent(
                entry.key.toString(),
                TextEditingController.new,
              ),
              decoration: InputDecoration(labelText: entry.key.toString()),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () =>
              unawaited(widget.onElicitation(widget.request, action: 'cancel')),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => unawaited(
            widget.onElicitation(widget.request, action: 'decline'),
          ),
          child: const Text('Decline'),
        ),
        if (supported)
          FilledButton(
            onPressed: () => unawaited(
              widget.onElicitation(
                widget.request,
                action: 'accept',
                content: <String, Object?>{
                  for (final entry in _fields.entries)
                    entry.key: _codexElicitationValue(
                      properties[entry.key],
                      entry.value.text,
                    ),
                },
              ),
            ),
            child: const Text('Accept'),
          ),
      ],
    );
  }
}

Object _codexElicitationValue(Object? schema, String value) {
  final type = schema is Map ? schema['type']?.toString() : null;
  if (type == 'number') return double.tryParse(value) ?? 0;
  if (type == 'integer') return int.tryParse(value) ?? 0;
  if (type == 'boolean') return value.toLowerCase() == 'true';
  return value;
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
