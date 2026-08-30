part of 'mobile_codex_chat_screen.dart';

class _MobileInteractionDock extends StatelessWidget {
  const _MobileInteractionDock({required this.state, required this.controller});

  final MobileCodexState state;
  final MobileCodexController controller;

  @override
  Widget build(BuildContext context) {
    final request = state.pendingRequests.firstOrNull;
    final child = request == null
        ? _MobilePlanPrompt(state: state, controller: controller)
        : request.isApproval
        ? _MobileApprovalCard(request: request, controller: controller)
        : request.isQuestion
        ? _MobileQuestionCard(
            key: ValueKey<Object>(request.id),
            request: request,
            state: state,
            controller: controller,
          )
        : request.isElicitation
        ? _MobileElicitationCard(
            key: ValueKey<Object>(request.id),
            request: request,
            controller: controller,
          )
        : _MobileRequestCard(
            title: 'Codex Request',
            body: request.description,
            actions: <Widget>[
              TextButton(
                onPressed: () => unawaited(controller.rejectRequest(request)),
                child: const Text('Decline'),
              ),
            ],
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space12,
        AleraTokens.space4,
        AleraTokens.space12,
        AleraTokens.space4,
      ),
      child: child,
    );
  }
}

class _MobileApprovalCard extends StatelessWidget {
  const _MobileApprovalCard({required this.request, required this.controller});

  final MobileCodexPendingRequest request;
  final MobileCodexController controller;

  @override
  Widget build(BuildContext context) => _MobileRequestCard(
    title: 'Codex Needs Approval',
    body: request.description,
    actions: <Widget>[
      if (request.supportsApprovalDecision('accept'))
        FilledButton(
          onPressed: () => _respond('accept'),
          child: const Text('Allow Once'),
        ),
      if (request.supportsApprovalDecision('acceptForSession'))
        TextButton(
          onPressed: () => _respond('acceptForSession'),
          child: const Text('Allow For Session'),
        ),
      if (request.supportsApprovalDecision('acceptWithExecpolicyAmendment'))
        TextButton(
          onPressed: () => _respond('acceptWithExecpolicyAmendment'),
          child: const Text('Allow Matching Commands'),
        ),
      if (request.supportsApprovalDecision('applyNetworkPolicyAmendment'))
        TextButton(
          onPressed: () => _respond('applyNetworkPolicyAmendment'),
          child: const Text('Apply Network Rule'),
        ),
      if (request.supportsApprovalDecision('decline'))
        TextButton(
          onPressed: () => _respond('decline'),
          child: const Text('Decline'),
        ),
      if (request.supportsApprovalDecision('cancel'))
        TextButton(
          onPressed: () => _respond('cancel'),
          child: const Text('Cancel Turn'),
        ),
    ],
  );

  void _respond(String decision) => unawaited(
    controller.respondApproval(
      request,
      decision: request.approvalDecisionValue(decision),
    ),
  );
}

class _MobileQuestionCard extends StatefulWidget {
  const _MobileQuestionCard({
    super.key,
    required this.request,
    required this.state,
    required this.controller,
  });

  final MobileCodexPendingRequest request;
  final MobileCodexState state;
  final MobileCodexController controller;

  @override
  State<_MobileQuestionCard> createState() => _MobileQuestionCardState();
}

class _MobileQuestionCardState extends State<_MobileQuestionCard> {
  final Map<String, List<String>> _answers = <String, List<String>>{};
  final Map<String, TextEditingController> _custom =
      <String, TextEditingController>{};
  final Set<String> _editing = <String>{};
  var _index = 0;
  var _submitting = false;
  var _autoResolutionSnoozed = false;

  @override
  void dispose() {
    for (final controller in _custom.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final questions = widget.request.questions;
    final question = questions[_index];
    final custom = _custom.putIfAbsent(question.id, TextEditingController.new);
    final title = question.header ?? question.question;
    return Container(
      decoration: BoxDecoration(
        color: AleraTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (questions.length > 1) ...<Widget>[
                IconButton(
                  tooltip: 'Previous Question',
                  visualDensity: VisualDensity.compact,
                  onPressed: _submitting || _index == 0
                      ? null
                      : () {
                          _recordInteraction();
                          setState(() => _index--);
                        },
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('${_index + 1} of ${questions.length}'),
                IconButton(
                  tooltip: 'Next Question',
                  visualDensity: VisualDensity.compact,
                  onPressed: _submitting || _index == questions.length - 1
                      ? null
                      : () {
                          _recordInteraction();
                          setState(() => _index++);
                        },
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
              IconButton(
                tooltip: 'Skip Questions',
                visualDensity: VisualDensity.compact,
                onPressed: _submitting ? null : _skip,
                icon: const Icon(Icons.close, size: AleraTokens.space16),
              ),
            ],
          ),
          if (question.header != null) ...<Widget>[
            const SizedBox(height: AleraTokens.space4),
            Text(question.question),
          ],
          const SizedBox(height: AleraTokens.space6),
          for (final (optionIndex, option)
              in question.options.indexed) ...<Widget>[
            _MobileChoiceRow(
              leading: '${optionIndex + 1}',
              title: option.label,
              description: option.description,
              selected: _answers[question.id]?.contains(option.label) == true,
              trailing: Icons.chevron_right,
              onTap: _submitting
                  ? null
                  : () => unawaited(_select(question, option.label)),
            ),
            if (optionIndex != question.options.length - 1)
              const SizedBox(height: AleraTokens.space4),
          ],
          if (question.isMultiSelect &&
              _answers[question.id]?.isNotEmpty == true)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _submitting
                    ? null
                    : () => unawaited(_advanceOrSubmit()),
                child: Text(_index == questions.length - 1 ? 'Submit' : 'Next'),
              ),
            ),
          if (question.options.isEmpty || question.isOther) ...<Widget>[
            const SizedBox(height: AleraTokens.space6),
            _MobileInlineAnswer(
              controller: custom,
              active: _editing.contains(question.id),
              hintText: question.options.isEmpty
                  ? 'Enter your answer'
                  : 'No, and tell Codex what to do differently',
              submitLabel: _index == questions.length - 1 ? 'Submit' : 'Next',
              obscureText: question.isSecret,
              onActivate: _submitting
                  ? null
                  : () {
                      _recordInteraction();
                      setState(() => _editing.add(question.id));
                    },
              onSubmit: _submitting
                  ? null
                  : () => unawaited(_submitCustom(question)),
              onSkip: _submitting ? null : _skip,
            ),
          ],
          if (widget.request.isImplementPlanQuestion) ...<Widget>[
            const SizedBox(height: AleraTokens.space8),
            Align(
              alignment: Alignment.centerLeft,
              child: _MobileModelMenuButton(
                key: const ValueKey<String>('mobile-codex-plan-model-selector'),
                state: widget.state,
                onModel: widget.controller.setModel,
                onReasoning: widget.controller.setReasoning,
                onSpeed: widget.controller.setSpeed,
                onCollaboration: widget.controller.setCollaborationMode,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _select(MobileCodexQuestion question, String value) async {
    if (_submitting) return;
    _recordInteraction();
    final current = <String>[...?_answers[question.id]];
    if (question.isMultiSelect) {
      current.contains(value) ? current.remove(value) : current.add(value);
    } else {
      _custom[question.id]?.clear();
      _editing.remove(question.id);
      current
        ..clear()
        ..add(value);
    }
    _answers[question.id] = current;
    if (!question.isMultiSelect) {
      await _advanceOrSubmit();
    } else {
      setState(() {});
    }
  }

  Future<void> _submitCustom(MobileCodexQuestion question) async {
    if (_submitting) return;
    final controller = _custom[question.id];
    final value = controller?.text.trim() ?? '';
    if (value.isEmpty) return;
    if (!question.isMultiSelect) {
      _answers[question.id] = <String>[value];
    }
    _editing.remove(question.id);
    await _advanceOrSubmit();
  }

  Future<void> _advanceOrSubmit() async {
    if (_submitting) return;
    _recordInteraction();
    final questions = widget.request.questions;
    if (_index < questions.length - 1) {
      setState(() => _index++);
      return;
    }
    setState(() => _submitting = true);
    await widget.controller.respondQuestion(
      widget.request,
      <String, List<String>>{
        for (final question in questions) question.id: _answerFor(question),
      },
    );
    if (mounted) setState(() => _submitting = false);
  }

  List<String> _answerFor(MobileCodexQuestion question) {
    final selected = _answers[question.id] ?? const <String>[];
    final custom = _custom[question.id]?.text.trim() ?? '';
    if (custom.isEmpty) return selected;
    if (!question.isMultiSelect) return <String>[custom];
    return <String>[...selected, if (!selected.contains(custom)) custom];
  }

  Future<void> _skip() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final answers = <String, List<String>>{
      for (final question in widget.request.questions)
        question.id: const <String>[],
    };
    await widget.controller.respondQuestion(widget.request, answers);
    if (mounted) setState(() => _submitting = false);
  }

  void _recordInteraction() {
    if (_autoResolutionSnoozed || widget.request.isBlocking) return;
    _autoResolutionSnoozed = true;
    unawaited(widget.controller.snoozeQuestionAutoResolution(widget.request));
  }
}

class _MobileChoiceRow extends StatelessWidget {
  const _MobileChoiceRow({
    required this.leading,
    required this.title,
    required this.onTap,
    this.description,
    this.trailing,
    this.selected = false,
  });

  final String leading;
  final String title;
  final String? description;
  final IconData? trailing;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AleraTokens.surfaceVariant : Colors.transparent,
    borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
    child: InkWell(
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space8,
          vertical: AleraTokens.space6,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: AleraTokens.space32,
              height: AleraTokens.space32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AleraTokens.border),
              ),
              child: Text(leading),
            ),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.labelLarge),
                  if (description?.trim().isNotEmpty == true) ...<Widget>[
                    const SizedBox(height: AleraTokens.space2),
                    Text(
                      description!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(
              width: AleraTokens.space32,
              child: trailing == null
                  ? null
                  : Icon(trailing, size: AleraTokens.space16),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MobileInlineAnswer extends StatelessWidget {
  const _MobileInlineAnswer({
    required this.controller,
    required this.active,
    required this.hintText,
    required this.submitLabel,
    required this.obscureText,
    required this.onActivate,
    required this.onSubmit,
    required this.onSkip,
  });

  final TextEditingController controller;
  final bool active;
  final String hintText;
  final String submitLabel;
  final bool obscureText;
  final VoidCallback? onActivate;
  final VoidCallback? onSubmit;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) => Material(
    color: active ? AleraTokens.surfaceVariant : Colors.transparent,
    borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
    child: InkWell(
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      onTap: onActivate,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space8,
          vertical: AleraTokens.space4,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            const Icon(Icons.edit_outlined, size: AleraTokens.space16),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: active
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: AleraTokens.codexInlineEditorMaxHeight,
                      ),
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        obscureText: obscureText,
                        minLines: 1,
                        maxLines: obscureText ? 1 : 5,
                        decoration: InputDecoration.collapsed(
                          hintText: hintText,
                        ),
                        onSubmitted: (_) => onSubmit?.call(),
                      ),
                    )
                  : Text(
                      hintText,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
            ),
            const SizedBox(width: AleraTokens.space8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) => TextButton(
                onPressed: onSubmit == null && onSkip == null
                    ? null
                    : active && value.text.trim().isNotEmpty
                    ? onSubmit
                    : onSkip,
                child: Text(
                  active && value.text.trim().isNotEmpty ? submitLabel : 'Skip',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
