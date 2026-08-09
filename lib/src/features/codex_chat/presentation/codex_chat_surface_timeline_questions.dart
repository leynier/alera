part of 'codex_chat_surface.dart';

String _codexQuestionCardStateKey(String tabId, CodexPendingRequest request) =>
    jsonEncode(<Object?>[
      tabId,
      request.id,
      request.method,
      for (final question in request.questions)
        <Object?>[
          question.id,
          question.question,
          question.header,
          question.isOther,
          question.isSecret,
          question.isMultiSelect,
          for (final option in question.options)
            <Object?>[option.label, option.description],
        ],
    ]);

class _CodexQuestionDraft {
  _CodexQuestionDraft(CodexPendingRequest request)
    : questions = request.questions,
      textControllers = <String, TextEditingController>{
        for (final question in request.questions)
          question.id: TextEditingController(),
      },
      selections = <String, Set<String>>{
        for (final question in request.questions) question.id: <String>{},
      };

  final List<CodexQuestion> questions;
  final Map<String, TextEditingController> textControllers;
  final Map<String, Set<String>> selections;
  int page = 0;
  bool autoResolutionSnoozed = false;

  void dispose() {
    for (final controller in textControllers.values) {
      controller.dispose();
    }
  }
}

class _CodexQuestionDock extends StatelessWidget {
  const _CodexQuestionDock({
    required this.card,
    required this.state,
    required this.showModelSelector,
    required this.onModelChanged,
    required this.onReasoningChanged,
    required this.onSpeedChanged,
    required this.onCollaborationChanged,
  });

  final Widget card;
  final CodexChatState state;
  final bool showModelSelector;
  final ValueChanged<String?> onModelChanged;
  final ValueChanged<String> onReasoningChanged;
  final ValueChanged<String> onSpeedChanged;
  final ValueChanged<String?> onCollaborationChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AleraTokens.space24,
      AleraTokens.space8,
      AleraTokens.space24,
      AleraTokens.space12,
    ),
    child: Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: AleraTokens.codexQuestionCardMaxWidth,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Flexible(fit: FlexFit.loose, child: card),
            if (showModelSelector) ...<Widget>[
              const SizedBox(height: AleraTokens.space6),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space16,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _CodexModelConfigurationControl(
                    state: state,
                    onModelChanged: onModelChanged,
                    onReasoningChanged: onReasoningChanged,
                    onSpeedChanged: onSpeedChanged,
                    onCollaborationChanged: onCollaborationChanged,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _CodexQuestionCard extends StatefulWidget {
  const _CodexQuestionCard({
    super.key,
    required this.request,
    required this.draft,
    required this.onQuestion,
    required this.onInteraction,
  });

  final CodexPendingRequest request;
  final _CodexQuestionDraft draft;
  final Future<void> Function(
    CodexPendingRequest request,
    Map<String, List<String>> answers,
  )
  onQuestion;
  final ValueChanged<CodexPendingRequest> onInteraction;

  @override
  State<_CodexQuestionCard> createState() => _CodexQuestionCardState();
}

class _CodexQuestionCardState extends State<_CodexQuestionCard> {
  static const Duration _enterGuardDuration = Duration(milliseconds: 350);

  late final DateTime _mountedAt;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _mountedAt = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final questions = widget.draft.questions;
    final page = widget.draft.page;
    final question = questions[page];
    final selections = widget.draft.selections[question.id]!;
    final editingOther = selections.contains(_CodexPromptOptionRow.otherValue);
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) => _handleKeyEvent(event),
      child: _CodexPromptFrame(
        frameKey: const ValueKey<String>('codex-question-card'),
        header: _CodexPromptHeader(
          title: question.question,
          page: page,
          pageCount: questions.length,
          onPrevious: page == 0
              ? null
              : () {
                  _recordInteraction();
                  setState(() => widget.draft.page--);
                },
          onNext: page == questions.length - 1
              ? null
              : () {
                  _recordInteraction();
                  setState(() => widget.draft.page++);
                },
          onClose: _submitting ? null : _skip,
        ),
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final entry in question.options.asMap().entries)
              _CodexPromptOptionRow(
                index: entry.key + 1,
                label: entry.value.displayLabel,
                description: entry.value.description,
                recommended: entry.value.isRecommended,
                selected: selections.contains(entry.value.label),
                onTap: _submitting
                    ? null
                    : () => _selectOption(question, entry.value.label),
              ),
            if (question.isOther && editingOther)
              _CodexPromptInlineAnswerRow(
                controller: widget.draft.textControllers[question.id]!,
                hintText: 'Tell Codex what to do differently',
                actionLabel: page == questions.length - 1 ? 'Submit' : 'Next',
                obscureText: question.isSecret,
                onChanged: () {
                  _recordInteraction();
                  setState(() {});
                },
                onSkip: _submitting ? null : _skip,
                onSubmit: _submitting
                    ? null
                    : () => _continueFromText(question),
              )
            else if (question.isOther)
              _CodexPromptOptionRow.other(
                label: 'No, and tell Codex what to do differently',
                selected: false,
                onTap: _submitting ? null : () => _selectOther(question),
                trailing: _CodexSkipButton(
                  onPressed: _submitting ? null : _skip,
                ),
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: _CodexSkipButton(onPressed: _submitting ? null : _skip),
              ),
            if (question.options.isEmpty && !question.isOther) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              TextField(
                key: ValueKey<String>('question-answer-${question.id}'),
                controller: widget.draft.textControllers[question.id],
                autofocus: true,
                obscureText: question.isSecret,
                enabled: !_submitting,
                textInputAction: page == questions.length - 1
                    ? TextInputAction.send
                    : TextInputAction.next,
                onTap: _recordInteraction,
                onSubmitted: (_) => _continueFromText(question),
                onChanged: (_) => _recordInteraction(),
                decoration: InputDecoration(
                  hintText: 'Enter your answer',
                  isDense: true,
                  suffixIcon: AleraIconButton(
                    tooltip: page == questions.length - 1
                        ? 'Submit Answer'
                        : 'Next Question',
                    onPressed: _submitting
                        ? null
                        : () => _continueFromText(question),
                    icon: page == questions.length - 1
                        ? AleraIcons.check
                        : AleraIcons.chevronRight,
                  ),
                ),
              ),
            ],
            if (question.isMultiSelect && !editingOther) ...<Widget>[
              const SizedBox(height: AleraTokens.space8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _submitting || selections.isEmpty
                      ? null
                      : _advanceOrSubmit,
                  child: Text(
                    page == questions.length - 1 ? 'Submit' : 'Continue',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      unawaited(_skip());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter &&
        DateTime.now().difference(_mountedAt) < _enterGuardDuration) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _selectOption(CodexQuestion question, String value) {
    _recordInteraction();
    final selections = widget.draft.selections[question.id]!;
    setState(() {
      if (question.isMultiSelect) {
        selections.contains(value)
            ? selections.remove(value)
            : selections.add(value);
      } else {
        selections
          ..clear()
          ..add(value);
      }
    });
    if (!question.isMultiSelect) unawaited(_advanceOrSubmit());
  }

  void _selectOther(CodexQuestion question) {
    _recordInteraction();
    setState(() {
      final selections = widget.draft.selections[question.id]!;
      if (question.isMultiSelect) {
        selections.add(_CodexPromptOptionRow.otherValue);
      } else {
        selections
          ..clear()
          ..add(_CodexPromptOptionRow.otherValue);
      }
    });
  }

  Future<void> _continueFromText(CodexQuestion question) async {
    if (widget.draft.textControllers[question.id]!.text.trim().isEmpty) return;
    await _advanceOrSubmit();
  }

  Future<void> _advanceOrSubmit() async {
    _recordInteraction();
    if (widget.draft.page < widget.draft.questions.length - 1) {
      setState(() => widget.draft.page++);
      return;
    }
    await _submit();
  }

  Future<void> _skip() => _submit(skip: true);

  void _recordInteraction() {
    if (widget.draft.autoResolutionSnoozed || widget.request.isBlocking) return;
    widget.draft.autoResolutionSnoozed = true;
    widget.onInteraction(widget.request);
  }

  Future<void> _submit({bool skip = false}) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    final answers = <String, List<String>>{};
    if (!skip) {
      for (final question in widget.draft.questions) {
        final selected =
            widget.draft.selections[question.id] ?? const <String>{};
        final custom =
            widget.draft.textControllers[question.id]?.text.trim() ?? '';
        answers[question.id] = <String>[
          for (final value in selected)
            if (value != _CodexPromptOptionRow.otherValue) value,
          if ((selected.contains(_CodexPromptOptionRow.otherValue) ||
                  question.options.isEmpty) &&
              custom.isNotEmpty)
            custom,
        ];
      }
    }
    await widget.onQuestion(widget.request, answers);
    if (mounted) setState(() => _submitting = false);
  }
}

class _CodexPromptFrame extends StatelessWidget {
  const _CodexPromptFrame({
    required this.frameKey,
    required this.header,
    required this.body,
  });

  final Key frameKey;
  final Widget header;
  final Widget body;

  @override
  Widget build(BuildContext context) => Container(
    key: frameKey,
    constraints: const BoxConstraints(
      maxHeight: AleraTokens.codexQuestionCardMaxHeight,
    ),
    padding: const EdgeInsets.symmetric(
      horizontal: AleraTokens.space12,
      vertical: AleraTokens.space8,
    ),
    decoration: BoxDecoration(
      color: AleraTokens.surfaceElevated,
      borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
      border: Border.all(color: AleraTokens.borderSubtle),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          key: const ValueKey<String>('codex-prompt-header-inset'),
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space4),
          child: header,
        ),
        const SizedBox(height: AleraTokens.space6),
        Flexible(child: SingleChildScrollView(child: body)),
      ],
    ),
  );
}

class _CodexPromptHeader extends StatelessWidget {
  const _CodexPromptHeader({
    required this.title,
    required this.onClose,
    this.closeTooltip = 'Skip Questions',
    this.page = 0,
    this.pageCount = 1,
    this.onPrevious,
    this.onNext,
  });

  final String title;
  final int page;
  final int pageCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final Future<void> Function()? onClose;
  final String closeTooltip;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      if (pageCount > 1) ...<Widget>[
        const SizedBox(width: AleraTokens.space12),
        AleraIconButton(
          tooltip: 'Previous Question',
          onPressed: onPrevious,
          icon: AleraIcons.chevronLeft,
          minSize: AleraTokens.space24,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space4),
          child: Text(
            '${page + 1} of $pageCount',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ),
        AleraIconButton(
          tooltip: 'Next Question',
          onPressed: onNext,
          icon: AleraIcons.chevronRight,
          minSize: AleraTokens.space24,
        ),
      ],
      const SizedBox(width: AleraTokens.space4),
      AleraIconButton(
        tooltip: closeTooltip,
        onPressed: onClose == null ? null : () => unawaited(onClose!()),
        icon: AleraIcons.close,
        minSize: AleraTokens.space24,
      ),
    ],
  );
}
