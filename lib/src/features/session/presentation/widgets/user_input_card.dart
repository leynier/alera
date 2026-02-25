import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/session/domain/pending_user_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class UserInputCard extends StatefulWidget {
  const UserInputCard({
    super.key,
    required this.pendingUserInput,
    required this.onSubmit,
    required this.onDismiss,
  });

  final PendingUserInput pendingUserInput;
  final ValueChanged<Map<String, dynamic>> onSubmit;
  final VoidCallback onDismiss;

  @override
  State<UserInputCard> createState() => _UserInputCardState();
}

class _UserInputCardState extends State<UserInputCard> {
  static const String _localPlanFallbackQuestionId = 'implement_plan';
  static const Duration _enterGuardDuration = Duration(milliseconds: 350);

  late final Map<String, _QuestionState> _questionStates;
  late final DateTime _mountedAt;
  final FocusNode _cardFocusNode = FocusNode(debugLabel: 'user-input-card');
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _mountedAt = DateTime.now();
    _questionStates = <String, _QuestionState>{};
    for (final question in widget.pendingUserInput.questions) {
      final questionState = _QuestionState(question: question);
      if (widget.pendingUserInput.source ==
              PendingUserInputSource.localPlanFallback &&
          question.id == _localPlanFallbackQuestionId &&
          (question.options?.isNotEmpty ?? false)) {
        questionState.selectedOption = question.options!.first.label;
      }
      _questionStates[question.id] = questionState;
    }
  }

  @override
  void dispose() {
    _cardFocusNode.dispose();
    for (final s in _questionStates.values) {
      s.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final answers = <String, dynamic>{};
    for (final entry in _questionStates.entries) {
      final state = entry.value;
      final answer = state.buildAnswer();
      if (answer != null) {
        answers[entry.key] = answer;
      }
    }
    widget.onSubmit(answers);
  }

  bool _isQuestionSubmittable(
    UserInputQuestion question,
    _QuestionState state,
  ) {
    if (question.options != null) {
      final selected = state.selectedOption;
      if (selected == null) {
        return false;
      }
      if (selected == '__other__') {
        return state.textController.text.trim().isNotEmpty;
      }
      return true;
    }
    return state.textController.text.trim().isNotEmpty;
  }

  bool _isCurrentQuestionSubmittable() {
    final questions = widget.pendingUserInput.questions;
    final currentQuestion = questions[_currentPage];
    final currentState = _questionStates[currentQuestion.id]!;
    return _isQuestionSubmittable(currentQuestion, currentState);
  }

  void _onContinue() {
    if (!_isCurrentQuestionSubmittable()) {
      return;
    }
    final questions = widget.pendingUserInput.questions;
    if (_currentPage < questions.length - 1) {
      setState(() => _currentPage++);
    } else {
      _submit();
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        widget.onDismiss();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (DateTime.now().difference(_mountedAt) < _enterGuardDuration) {
          return KeyEventResult.handled;
        }
        _onContinue();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final questions = widget.pendingUserInput.questions;
    final currentQuestion = questions[_currentPage];
    final currentState = _questionStates[currentQuestion.id]!;
    final canContinue = _isQuestionSubmittable(currentQuestion, currentState);
    final isLastPage = _currentPage == questions.length - 1;
    final hasMultiplePages = questions.length > 1;
    return Focus(
      focusNode: _cardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Container(
        decoration: BoxDecoration(
          color: AleraTokens.surface,
          borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          border: Border.all(color: AleraTokens.border),
        ),
        padding: const EdgeInsets.all(AleraTokens.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Text(
                    currentQuestion.question,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (hasMultiplePages) ...<Widget>[
                  const SizedBox(width: AleraTokens.space8),
                  _PaginationControl(
                    currentPage: _currentPage,
                    totalPages: questions.length,
                    onPrevious: _currentPage > 0
                        ? () => setState(() => _currentPage--)
                        : null,
                    onNext: _currentPage < questions.length - 1
                        ? () => setState(() => _currentPage++)
                        : null,
                  ),
                ],
              ],
            ),
            const SizedBox(height: AleraTokens.space12),
            _QuestionWidget(
              question: currentQuestion,
              questionState: currentState,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: AleraTokens.space12),
            Row(
              children: <Widget>[
                TextButton(
                  onPressed: widget.onDismiss,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AleraTokens.space8,
                      vertical: AleraTokens.space4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Dismiss'),
                ),
                const SizedBox(width: AleraTokens.space6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AleraTokens.space4,
                    vertical: AleraTokens.space2,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: AleraTokens.border),
                    borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                  ),
                  child: const Text(
                    'ESC',
                    style: TextStyle(
                      fontSize: 11,
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: canContinue ? _onContinue : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(80, 32),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AleraTokens.space16,
                      vertical: AleraTokens.space8,
                    ),
                  ),
                  icon: const Icon(Icons.keyboard_return, size: 14),
                  label: Text(isLastPage ? 'Submit' : 'Continue'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PaginationControl extends StatelessWidget {
  const _PaginationControl({
    required this.currentPage,
    required this.totalPages,
    required this.onPrevious,
    required this.onNext,
  });

  final int currentPage;
  final int totalPages;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left, size: 16),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          tooltip: 'Previous',
        ),
        Text(
          '${currentPage + 1} of $totalPages',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AleraTokens.foregroundMuted),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right, size: 16),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          tooltip: 'Next',
        ),
      ],
    );
  }
}

class _QuestionState {
  _QuestionState({required this.question})
    : textController = TextEditingController(),
      selectedOption = null;

  final UserInputQuestion question;
  final TextEditingController textController;
  String? selectedOption;

  void dispose() {
    textController.dispose();
  }

  Map<String, dynamic>? buildAnswer() {
    if (question.options != null) {
      final selected = selectedOption;
      if (selected == null && !question.isOther) {
        return null;
      }
      if (question.isOther && selectedOption == null) {
        final custom = textController.text.trim();
        if (custom.isEmpty) {
          return null;
        }
        return <String, dynamic>{
          'answers': <String>[custom],
        };
      }
      final answers = <String>[];
      if (selected != null) {
        answers.add(selected);
      }
      if (question.isOther && textController.text.trim().isNotEmpty) {
        answers.add(textController.text.trim());
      }
      return <String, dynamic>{'answers': answers};
    }
    final text = textController.text.trim();
    if (text.isEmpty) {
      return null;
    }
    return <String, dynamic>{
      'answers': <String>[text],
    };
  }
}

class _QuestionWidget extends StatefulWidget {
  const _QuestionWidget({
    required this.question,
    required this.questionState,
    required this.onChanged,
  });

  final UserInputQuestion question;
  final _QuestionState questionState;
  final VoidCallback onChanged;

  @override
  State<_QuestionWidget> createState() => _QuestionWidgetState();
}

class _QuestionWidgetState extends State<_QuestionWidget> {
  void _selectOption(String value) {
    setState(() => widget.questionState.selectedOption = value);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    if (q.options != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ...q.options!.asMap().entries.map((entry) {
            final i = entry.key;
            final opt = entry.value;
            final isSelected = widget.questionState.selectedOption == opt.label;
            return _OptionRow(
              label: '${i + 1}.  ${opt.label}',
              description: opt.description.isNotEmpty ? opt.description : null,
              isSelected: isSelected,
              onTap: () => _selectOption(opt.label),
            );
          }),
          if (q.isOther) ...<Widget>[
            _OptionRow(
              label:
                  q.otherLabel ?? 'No, and tell Alera what to do differently',
              isSelected: widget.questionState.selectedOption == '__other__',
              onTap: () => _selectOption('__other__'),
            ),
            if (widget.questionState.selectedOption == '__other__')
              Padding(
                padding: const EdgeInsets.only(top: AleraTokens.space8),
                child: TextField(
                  controller: widget.questionState.textController,
                  onChanged: (_) => widget.onChanged(),
                  decoration: const InputDecoration(
                    hintText: 'Enter your answer',
                    isDense: true,
                  ),
                  autofocus: true,
                ),
              ),
          ],
        ],
      );
    }
    return TextField(
      controller: widget.questionState.textController,
      obscureText: q.isSecret,
      onChanged: (_) => widget.onChanged(),
      decoration: const InputDecoration(
        hintText: 'Enter your answer',
        isDense: true,
      ),
      autofocus: true,
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.description,
  });

  final String label;
  final String? description;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space8,
          vertical: AleraTokens.space6,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AleraTokens.surfaceElevated : Colors.transparent,
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isSelected
                    ? AleraTokens.foreground
                    : AleraTokens.foregroundMuted,
              ),
            ),
            if (description != null) ...<Widget>[
              const SizedBox(height: AleraTokens.space2),
              Text(
                description!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundFaint,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
