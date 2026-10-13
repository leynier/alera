import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_question_option_row.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// What the user has entered for one pending question request. The dock owns
/// it, so paging between requests or rebuilding the card keeps the answers;
/// [dispose] releases the free-text controllers.
class AgentChatQuestionDraft {
  final Map<String, Set<int>> _selections = <String, Set<int>>{};
  final Map<String, TextEditingController> _customAnswers =
      <String, TextEditingController>{};
  final Set<String> _openCustomAnswers = <String>{};

  /// Index of the question on screen.
  int page = 0;

  /// Indexes of the options picked for [question].
  Set<int> selectionsOf(AgentChatQuestion question) =>
      _selections.putIfAbsent(question.id, () => <int>{});

  TextEditingController customAnswerOf(AgentChatQuestion question) =>
      _customAnswers.putIfAbsent(
        question.id,
        () => TextEditingController(text: question.initialAnswer ?? ''),
      );

  /// Whether the free-text field of [question] is on screen. A question
  /// without options has nothing else to answer with.
  bool showsCustomAnswer(AgentChatQuestion question) =>
      question.options.isEmpty || _openCustomAnswers.contains(question.id);

  void openCustomAnswer(AgentChatQuestion question) {
    _openCustomAnswers.add(question.id);
  }

  void closeCustomAnswer(AgentChatQuestion question) {
    _openCustomAnswers.remove(question.id);
  }

  /// The picked options' answer values in the order the agent listed them,
  /// then the free text while its field is on screen and holds any.
  List<String> answersOf(AgentChatQuestion question) {
    final selections = selectionsOf(question);
    final custom = showsCustomAnswer(question)
        ? customAnswerOf(question).text
        : '';
    return <String>[
      for (final (index, option) in question.options.indexed)
        if (selections.contains(index)) option.answerValue,
      if (custom.trim().isNotEmpty) question.secret ? custom : custom.trim(),
    ];
  }

  bool hasAnswer(AgentChatQuestion question) => answersOf(question).isNotEmpty;

  AgentChatUserInputResponse responseFor(AgentChatRequest request) =>
      AgentChatUserInputResponse(<String, List<String>>{
        for (final question in request.questions)
          question.id: answersOf(question),
      });

  void dispose() {
    for (final controller in _customAnswers.values) {
      controller.dispose();
    }
  }
}

/// The question of a pending request that is on screen: its options, a
/// free-text answer when the agent allows one, and Skip. Picking an option of
/// a single-choice question moves on at once, and the last answer sends the
/// whole request. While the card has focus, 1-9 pick an option and Escape
/// skips the request; Escape in a free-text answer opened with Write Another
/// Answer closes that answer instead.
class const AgentChatQuestionCard({
  super.key,
  required final AgentChatRequest request,
  required final AgentChatQuestionDraft draft,
  required final bool responding,
  required final bool enabled,
  required final Future<void> Function(
    AgentChatRequest request,
    AgentChatResponse response,
  )
  onRespond,
  final bool takeFocus = false,
}) extends StatefulWidget {
  /// How long after the card appears an Enter is still taken to be the one
  /// that sent the previous message, and ignored.
  static const Duration enterGuard = Duration(milliseconds: 350);

  @override
  State<AgentChatQuestionCard> createState() => _AgentChatQuestionCardState();
}

class _AgentChatQuestionCardState extends State<AgentChatQuestionCard> {
  static const List<LogicalKeyboardKey> _digitKeys = <LogicalKeyboardKey>[
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
  static const List<LogicalKeyboardKey> _numpadKeys = <LogicalKeyboardKey>[
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];

  final FocusNode _cardFocus = FocusNode(
    debugLabel: 'Agent chat question card',
    skipTraversal: true,
  );
  final FocusNode _answerFocus = FocusNode(
    debugLabel: 'Agent chat question answer',
  );
  late final Timer _enterGuard;
  late final bool _answerFieldFirst;
  bool _submitting = false;

  List<AgentChatQuestion> get _questions => widget.request.questions;

  int get _page => widget.draft.page.clamp(0, _questions.length - 1);

  AgentChatQuestion get _question => _questions[_page];

  bool get _lastPage => _page >= _questions.length - 1;

  bool get _busy => widget.responding || _submitting;

  bool get _canAnswer => widget.enabled && !_busy;

  @override
  void initState() {
    super.initState();
    _enterGuard = Timer(AgentChatQuestionCard.enterGuard, () {});
    _answerFieldFirst =
        _questions.isNotEmpty && widget.draft.showsCustomAnswer(_question);
    if (widget.takeFocus) _focusEntryAfterFrame();
  }

  @override
  void dispose() {
    _enterGuard.cancel();
    _cardFocus.dispose();
    _answerFocus.dispose();
    super.dispose();
  }

  void _focusEntryAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _questions.isEmpty) return;
      final showsAnswer = widget.draft.showsCustomAnswer(_question);
      (showsAnswer ? _answerFocus : _cardFocus).requestFocus();
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      return _enterGuard.isActive
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent || !_canAnswer) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.escape) {
      final question = _question;
      if (_answerFocus.hasFocus && question.options.isNotEmpty) {
        _closeCustomAnswer(question);
      } else {
        _skip();
      }
      return KeyEventResult.handled;
    }
    // Digits typed into the answer, and shortcuts such as Mod+1, are not
    // option picks.
    final keyboard = HardwareKeyboard.instance;
    if (_answerFocus.hasFocus ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    var index = _digitKeys.indexOf(key);
    if (index < 0) index = _numpadKeys.indexOf(key);
    final question = _question;
    if (index < 0 || index >= question.options.length) {
      return KeyEventResult.ignored;
    }
    _choose(question, index);
    return KeyEventResult.handled;
  }

  void _handleEnter() {
    if (_enterGuard.isActive || !_canAnswer) return;
    if (!widget.draft.hasAnswer(_question)) return;
    _advanceOrSubmit();
  }

  void _choose(AgentChatQuestion question, int index) {
    final draft = widget.draft;
    final selections = draft.selectionsOf(question);
    if (question.multiSelect) {
      setState(() {
        if (!selections.remove(index)) selections.add(index);
      });
      return;
    }
    setState(() {
      selections
        ..clear()
        ..add(index);
      draft.closeCustomAnswer(question);
    });
    _advanceOrSubmit();
  }

  void _openCustomAnswer(AgentChatQuestion question) {
    setState(() {
      widget.draft.openCustomAnswer(question);
      if (!question.multiSelect) widget.draft.selectionsOf(question).clear();
    });
    _focusEntryAfterFrame();
  }

  // The draft keeps the typed text, so reopening the answer brings it back.
  void _closeCustomAnswer(AgentChatQuestion question) {
    _cardFocus.requestFocus();
    setState(() => widget.draft.closeCustomAnswer(question));
  }

  void _goToPage(int page) {
    setState(() => widget.draft.page = page);
    _focusEntryAfterFrame();
  }

  void _advanceOrSubmit() {
    if (!_lastPage) {
      _goToPage(_page + 1);
      return;
    }
    unawaited(_respond(widget.draft.responseFor(widget.request)));
  }

  void _skip() => unawaited(
    _respond(const AgentChatUserInputResponse(<String, List<String>>{})),
  );

  // A click anywhere in the card hands it the keyboard, so 1-9 and Escape
  // work while the composer stays mounted below it.
  void _claimFocus(PointerDownEvent event) {
    if (!_answerFocus.hasFocus) _cardFocus.requestFocus();
  }

  Future<void> _respond(AgentChatResponse response) async {
    if (!_canAnswer) return;
    // Disabling the rows and the field would hand focus back to whatever
    // had it before the card; the card keeps it so the next request can.
    if (_cardFocus.hasFocus) _cardFocus.requestFocus();
    setState(() => _submitting = true);
    try {
      await widget.onRespond(widget.request, response);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_questions.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final question = _question;
    final canAnswer = _canAnswer;
    return Focus(
      focusNode: _cardFocus,
      autofocus: !_answerFieldFirst,
      onKeyEvent: _handleKeyEvent,
      child: Listener(
        onPointerDown: _claimFocus,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: AleraTokens.agentChatQuestionCardMaxHeight,
          ),
          child: Material(
            color: AleraTokens.surfaceElevated,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AleraTokens.radiusXl),
              side: const BorderSide(color: AleraTokens.borderSubtle),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AleraTokens.space12),
              child: _buildBody(theme, question, canAnswer: canAnswer),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    ThemeData theme,
    AgentChatQuestion question, {
    required bool canAnswer,
  }) {
    final draft = widget.draft;
    final selections = draft.selectionsOf(question);
    final showsAnswer = draft.showsCustomAnswer(question);
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        ?_buildTopBar(theme, question),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(bottom: AleraTokens.space8),
                  child: Text(
                    question.question,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: .w600,
                    ),
                  ),
                ),
                for (final (index, option) in question.options.indexed)
                  AgentChatQuestionOptionRow(
                    number: index + 1,
                    label: option.label,
                    description: option.description,
                    selected: selections.contains(index),
                    advances: !question.multiSelect,
                    onTap: canAnswer ? () => _choose(question, index) : null,
                  ),
                if (showsAnswer)
                  AgentChatQuestionAnswerField(
                    controller: draft.customAnswerOf(question),
                    focusNode: _answerFocus,
                    autofocus: _answerFieldFirst,
                    enabled: canAnswer,
                    secret: question.secret,
                    showMarker: question.options.isNotEmpty,
                    onChanged: (_) => setState(() {}),
                    onEnter: _handleEnter,
                  )
                else if (question.allowCustomAnswer)
                  AgentChatQuestionOptionRow(
                    icon: AleraIcons.edit,
                    label: 'Write Another Answer',
                    muted: true,
                    advances: false,
                    onTap: canAnswer ? () => _openCustomAnswer(question) : null,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AleraTokens.space12),
        _buildActions(question, showsAnswer: showsAnswer),
      ],
    );
  }

  Widget? _buildTopBar(ThemeData theme, AgentChatQuestion question) {
    final header = question.header.trim();
    final paged = _questions.length > 1;
    if (header.isEmpty && !paged && !_busy) return null;
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              header,
              maxLines: 1,
              overflow: .ellipsis,
              style: labelStyle,
            ),
          ),
          if (_busy) ...<Widget>[
            const SizedBox(width: AleraTokens.space8),
            const SizedBox.square(
              dimension: AleraTokens.iconMd,
              child: CircularProgressIndicator(
                strokeWidth: AleraTokens.strokeSm,
              ),
            ),
          ],
          if (paged) ...<Widget>[
            const SizedBox(width: AleraTokens.space8),
            AleraIconButton(
              tooltip: 'Previous Question',
              icon: AleraIcons.chevronLeft,
              minSize: AleraTokens.iconButtonSm,
              onPressed: _page > 0 ? () => _goToPage(_page - 1) : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space4,
              ),
              child: Text(
                '${_page + 1} of ${_questions.length}',
                style: labelStyle,
              ),
            ),
            AleraIconButton(
              tooltip: 'Next Question',
              icon: AleraIcons.chevronRight,
              minSize: AleraTokens.iconButtonSm,
              onPressed: _lastPage ? null : () => _goToPage(_page + 1),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActions(
    AgentChatQuestion question, {
    required bool showsAnswer,
  }) {
    final canAnswer = _canAnswer;
    final label = _lastPage
        ? 'Submit'
        : question.multiSelect
        ? 'Continue'
        : 'Next';
    return Row(
      mainAxisAlignment: .end,
      children: <Widget>[
        OutlinedButton(
          onPressed: canAnswer ? _skip : null,
          child: const Text('Skip'),
        ),
        // A single-choice option answers by itself; the button is for picks
        // that need confirming and for typed answers.
        if (question.multiSelect || showsAnswer) ...<Widget>[
          const SizedBox(width: AleraTokens.space8),
          FilledButton(
            onPressed: canAnswer && widget.draft.hasAnswer(question)
                ? _advanceOrSubmit
                : null,
            child: Text(label),
          ),
        ],
      ],
    );
  }
}
