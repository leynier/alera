part of 'mobile_codex_chat_screen.dart';

class _MobileTimelineCell extends StatefulWidget {
  const _MobileTimelineCell({required this.cell});

  final MobileCodexTimelineCell cell;

  @override
  State<_MobileTimelineCell> createState() => _MobileTimelineCellState();
}

class _MobileTimelineCellState extends State<_MobileTimelineCell> {
  late bool _collapsed =
      widget.cell.isCollapsed || _mobileDefaultCollapsed(widget.cell);

  @override
  void didUpdateWidget(covariant _MobileTimelineCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cell.id != widget.cell.id) {
      _collapsed =
          widget.cell.isCollapsed || _mobileDefaultCollapsed(widget.cell);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cell = widget.cell;
    if (cell.kind == 'turnSeparator') {
      return const Divider(height: AleraTokens.space24);
    }
    final color = cell.isUser
        ? AleraTokens.info
        : cell.isReasoning
        ? AleraTokens.foregroundMuted
        : cell.kind == 'command' || cell.kind == 'toolCall'
        ? AleraTokens.warning
        : cell.kind == 'diff'
        ? AleraTokens.success
        : AleraTokens.foreground;
    final collapseable =
        cell.kind == 'reasoning' ||
        cell.kind == 'toolCall' ||
        cell.kind == 'command' ||
        cell.kind == 'diff' ||
        cell.kind == 'subAgent' ||
        cell.kind == 'plan' ||
        cell.kind == 'questionAnswer';
    final body = _MobileCodexMarkdown(text: cell.displayText);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _mobileCellLabel(cell),
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(color: color),
              ),
            ),
            if (cell.isStreaming)
              const SizedBox(
                width: AleraTokens.iconSm,
                height: AleraTokens.iconSm,
                child: CircularProgressIndicator(
                  strokeWidth: AleraTokens.strokeSm,
                ),
              ),
            if (collapseable)
              IconButton(
                tooltip: _collapsed ? 'Expand Item' : 'Collapse Item',
                onPressed: () => setState(() => _collapsed = !_collapsed),
                icon: Icon(_collapsed ? Icons.expand_more : Icons.expand_less),
              ),
          ],
        ),
        if (!_collapsed) ...<Widget>[
          if (cell.subtitle != null)
            Text(cell.subtitle!, style: AleraTokens.monoStyle),
          const SizedBox(height: AleraTokens.space6),
          body,
          if (cell.status == 'failed')
            Text(
              'Codex could not complete this item.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AleraTokens.error),
            ),
        ],
      ],
    );
    if (cell.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AleraTokens.chatBubbleMaxWidth,
          ),
          child: Card(
            color: AleraTokens.surfaceVariant,
            margin: const EdgeInsets.only(bottom: AleraTokens.space12),
            child: Padding(
              padding: const EdgeInsets.all(AleraTokens.space12),
              child: body,
            ),
          ),
        ),
      );
    }
    final assistant = cell.isAssistant || cell.kind == 'progressText';
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space12),
      child: assistant
          ? content
          : Card(
              color: AleraTokens.surface,
              child: Padding(
                padding: const EdgeInsets.all(AleraTokens.space12),
                child: content,
              ),
            ),
    );
  }
}

bool _mobileDefaultCollapsed(MobileCodexTimelineCell cell) =>
    switch (cell.kind) {
      'reasoning' ||
      'toolCall' ||
      'command' ||
      'diff' ||
      'subAgent' ||
      'questionAnswer' ||
      'plan' => true,
      _ => false,
    };

class _MobileApprovalCard extends StatelessWidget {
  const _MobileApprovalCard({required this.request, required this.controller});

  final MobileCodexPendingRequest request;
  final MobileCodexController controller;

  @override
  Widget build(BuildContext context) => _MobileRequestCard(
    title: 'Codex Needs Approval',
    body: request.description,
    actions: <Widget>[
      TextButton(
        onPressed: () => unawaited(
          controller.respondApproval(
            request,
            decision: request.approvalDecisionValue('decline'),
          ),
        ),
        child: const Text('Decline'),
      ),
      FilledButton(
        onPressed: () => unawaited(
          controller.respondApproval(
            request,
            decision: request.approvalDecisionValue('accept'),
          ),
        ),
        child: const Text('Approve'),
      ),
      TextButton(
        onPressed: () => unawaited(
          controller.respondApproval(
            request,
            decision: request.approvalDecisionValue('acceptForSession'),
          ),
        ),
        child: const Text('Approve For Session'),
      ),
    ],
  );
}

class _MobileQuestionCard extends StatefulWidget {
  const _MobileQuestionCard({required this.request, required this.controller});

  final MobileCodexPendingRequest request;
  final MobileCodexController controller;

  @override
  State<_MobileQuestionCard> createState() => _MobileQuestionCardState();
}

class _MobileQuestionCardState extends State<_MobileQuestionCard> {
  final Map<String, TextEditingController> _text =
      <String, TextEditingController>{};
  final Map<String, Set<String>> _selected = <String, Set<String>>{};

  @override
  void dispose() {
    for (final controller in _text.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final questions = widget.request.questions;
    return _MobileRequestCard(
      title: 'Codex Needs Your Input',
      bodyWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            widget.request.isBlocking
                ? 'Response required.'
                : 'Response optional.',
          ),
          for (final question in questions) _question(question),
        ],
      ),
      actions: <Widget>[
        FilledButton(
          onPressed: () => unawaited(
            widget.controller.respondQuestion(
              widget.request,
              <String, List<String>>{
                for (final question in questions)
                  question.id:
                      question.isOther &&
                          (_text[question.id]?.text.trim().isNotEmpty ?? false)
                      ? <String>[_text[question.id]!.text.trim()]
                      : _selected[question.id]?.isNotEmpty == true
                      ? _selected[question.id]!.toList(growable: false)
                      : <String>[_text[question.id]?.text.trim() ?? ''],
              },
            ),
          ),
          child: const Text('Submit Answers'),
        ),
      ],
    );
  }

  Widget _question(MobileCodexQuestion question) {
    final text = _text.putIfAbsent(question.id, TextEditingController.new);
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
              children: <Widget>[
                for (final option in question.options)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: selected.contains(option.label),
                    onSelected: (value) => setState(() {
                      if (!question.isMultiSelect) selected.clear();
                      if (value) {
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
              controller: text,
              obscureText: question.isSecret,
              decoration: const InputDecoration(hintText: 'Your Answer'),
            ),
        ],
      ),
    );
  }
}

class _MobileElicitationCard extends StatefulWidget {
  const _MobileElicitationCard({
    required this.request,
    required this.controller,
  });

  final MobileCodexPendingRequest request;
  final MobileCodexController controller;

  @override
  State<_MobileElicitationCard> createState() => _MobileElicitationCardState();
}

class _MobileElicitationCardState extends State<_MobileElicitationCard> {
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
    final request = widget.request;
    final properties = request.elicitationSchema['properties'];
    final isSupported =
        request.hasSupportedElicitationForm && properties is Map;
    return _MobileRequestCard(
      title: 'MCP Server Needs Input',
      bodyWidget: isSupported
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final entry in Map<Object?, Object?>.from(
                  properties,
                ).entries)
                  _field(entry.key.toString(), entry.value),
              ],
            )
          : const Text('This MCP input form is not supported on mobile.'),
      actions: <Widget>[
        TextButton(
          onPressed: () => unawaited(
            widget.controller.respondElicitation(request, action: 'cancel'),
          ),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => unawaited(
            widget.controller.respondElicitation(request, action: 'decline'),
          ),
          child: const Text('Decline'),
        ),
        if (isSupported)
          FilledButton(
            onPressed: () => unawaited(
              widget.controller.respondElicitation(
                request,
                action: 'accept',
                content: <String, Object?>{
                  for (final entry in _fields.entries)
                    entry.key: _elicitationValue(
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

  Widget _field(String name, Object? schema) {
    final controller = _fields.putIfAbsent(name, TextEditingController.new);
    final schemaMap = schema is Map
        ? Map<Object?, Object?>.from(schema)
        : const <Object?, Object?>{};
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space8),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: name,
          hintText: schemaMap['description']?.toString(),
        ),
        obscureText: schemaMap['format'] == 'password',
      ),
    );
  }
}

Object _elicitationValue(Object? schema, String value) {
  final type = schema is Map ? schema['type']?.toString() : null;
  if (type == 'number') return double.tryParse(value) ?? 0;
  if (type == 'integer') return int.tryParse(value) ?? 0;
  if (type == 'boolean') return value.toLowerCase() == 'true';
  return value;
}

class _MobileError extends StatelessWidget {
  const _MobileError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: AleraTokens.contentPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: AleraTokens.space12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    ),
  );
}

String _mobileCellLabel(MobileCodexTimelineCell cell) {
  if (cell.isUser) return 'You';
  if (cell.isAssistant) return 'Codex';
  if (cell.isReasoning) return 'Reasoning';
  if (cell.kind == 'command') return cell.title ?? 'Command';
  if (cell.kind == 'toolCall') return cell.title ?? 'Tool Call';
  if (cell.kind == 'diff') return cell.title ?? 'File Changes';
  if (cell.kind == 'plan') return 'Plan';
  if (cell.kind == 'subAgent') return cell.title ?? 'Sub-Agent';
  return cell.title ?? 'Codex Activity';
}

class _MobilePlanPrompt extends StatelessWidget {
  const _MobilePlanPrompt({required this.controller});

  final MobileCodexController controller;

  @override
  Widget build(BuildContext context) => Card(
    color: AleraTokens.surfaceElevated,
    child: Padding(
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: AleraTokens.space8,
        runSpacing: AleraTokens.space8,
        children: <Widget>[
          const Text('Implement this plan?'),
          FilledButton(
            onPressed: () => unawaited(controller.implementPlan()),
            child: const Text('Implement Plan'),
          ),
          TextButton(
            onPressed: () => unawaited(controller.declinePlan()),
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
    if (value != null && value.trim().isNotEmpty) {
      await controller.refinePlan(value);
    }
  }
}
