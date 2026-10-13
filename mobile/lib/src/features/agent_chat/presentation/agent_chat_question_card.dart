import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_request_card.dart';
import 'package:flutter/material.dart';

/// Questions the agent asked, docked above the composer one at a time. A
/// single-choice answer advances on tap; the last answer sends them all.
class const AgentChatQuestionCard({
  super.key,
  required final AgentChatRequest request,
  required final bool enabled,
  required final AgentChatRespond onRespond,
}) extends StatefulWidget {
  @override
  State<AgentChatQuestionCard> createState() => _AgentChatQuestionCardState();
}

class _AgentChatQuestionCardState extends State<AgentChatQuestionCard> {
  final Map<String, List<String>> _selected = <String, List<String>>{};
  final Map<String, TextEditingController> _custom =
      <String, TextEditingController>{};
  int _index = 0;

  List<AgentChatQuestion> get _questions => widget.request.questions;

  @override
  void dispose() {
    for (final controller in _custom.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _customFor(AgentChatQuestion question) =>
      _custom.putIfAbsent(
        question.id,
        () => TextEditingController(text: question.initialAnswer ?? ''),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final question = _questions[_index.clamp(0, _questions.length - 1)];
    final last = _index >= _questions.length - 1;
    final selected = _selected[question.id] ?? const <String>[];
    final enabled = widget.enabled;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space8,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.border),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  question.header.isEmpty ? question.question : question.header,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (_questions.length > 1) ...<Widget>[
                IconButton(
                  tooltip: 'Previous Question',
                  onPressed: enabled && _index > 0
                      ? () => setState(() => _index -= 1)
                      : null,
                  icon: const Icon(AleraIcons.chevronUp),
                ),
                Text('${_index + 1} of ${_questions.length}'),
                IconButton(
                  tooltip: 'Next Question',
                  onPressed: enabled && !last
                      ? () => setState(() => _index += 1)
                      : null,
                  icon: const Icon(AleraIcons.chevronDown),
                ),
              ],
              IconButton(
                tooltip: 'Skip Questions',
                onPressed: enabled ? _skip : null,
                icon: const Icon(AleraIcons.close, size: AleraTokens.space16),
              ),
            ],
          ),
          if (question.header.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AleraTokens.space6),
              child: Text(question.question),
            ),
          for (final (index, option) in question.options.indexed)
            _ChoiceRow(
              ordinal: index + 1,
              option: option,
              selected: selected.contains(option.answerValue),
              multiSelect: question.multiSelect,
              onTap: enabled ? () => _choose(question, option) : null,
            ),
          if (question.allowCustomAnswer)
            Padding(
              padding: const EdgeInsets.only(top: AleraTokens.space6),
              child: TextField(
                controller: _customFor(question),
                enabled: enabled,
                obscureText: question.secret,
                minLines: 1,
                maxLines: question.secret ? 1 : AleraTokens.composeBarMaxLines,
                textInputAction: .done,
                decoration: InputDecoration(
                  hintText: question.options.isEmpty
                      ? 'Your answer'
                      : 'Or answer in your own words',
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: enabled && _answered(question)
                    ? (_) => _advance()
                    : null,
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: AleraTokens.space6),
              child: FilledButton(
                onPressed: enabled && _answered(question) ? _advance : null,
                child: Text(last ? 'Submit' : 'Next'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _answered(AgentChatQuestion question) =>
      (_selected[question.id]?.isNotEmpty ?? false) ||
      (_custom[question.id]?.text.trim().isNotEmpty ?? false);

  void _choose(AgentChatQuestion question, AgentChatQuestionOption option) {
    final current = <String>[...?_selected[question.id]];
    final value = option.answerValue;
    if (question.multiSelect) {
      current.contains(value) ? current.remove(value) : current.add(value);
      setState(() => _selected[question.id] = current);
      return;
    }
    _custom[question.id]?.clear();
    setState(() => _selected[question.id] = <String>[value]);
    _advance();
  }

  void _advance() {
    if (_index < _questions.length - 1) {
      setState(() => _index += 1);
      return;
    }
    unawaited(
      widget.onRespond(
        widget.request,
        AgentChatUserInputResponse(<String, List<String>>{
          for (final question in _questions) question.id: _answerFor(question),
        }),
      ),
    );
  }

  List<String> _answerFor(AgentChatQuestion question) {
    final selected = _selected[question.id] ?? const <String>[];
    final custom = _custom[question.id]?.text.trim() ?? '';
    if (custom.isEmpty) return selected;
    if (!question.multiSelect) return <String>[custom];
    return <String>[...selected, if (!selected.contains(custom)) custom];
  }

  void _skip() => unawaited(
    widget.onRespond(
      widget.request,
      const AgentChatUserInputResponse(<String, List<String>>{}),
    ),
  );
}

class const _ChoiceRow({
  required final int ordinal,
  required final AgentChatQuestionOption option,
  required final bool selected,
  required final bool multiSelect,
  required final VoidCallback? onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? AleraTokens.surfaceVariant : Colors.transparent,
      borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AleraTokens.minTapTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space8,
              vertical: AleraTokens.space6,
            ),
            child: Row(
              children: <Widget>[
                SizedBox.square(
                  dimension: AleraTokens.space32,
                  child: Center(
                    child: multiSelect
                        ? Icon(
                            selected ? AleraIcons.success : AleraIcons.circle,
                            size: AleraTokens.space16,
                          )
                        : Text('$ordinal', style: theme.textTheme.labelLarge),
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: <Widget>[
                      Text(option.label, style: theme.textTheme.labelLarge),
                      if (option.description.trim().isNotEmpty)
                        Text(
                          option.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AleraTokens.foregroundMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
