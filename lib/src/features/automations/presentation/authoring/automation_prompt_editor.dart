import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/automations/domain/automation_prompt_variables.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const List<AutomationPromptVariable> _quickVariables =
    <AutomationPromptVariable>[
      .automationName,
      .runNumber,
      .runScheduledAt,
      .workspaceName,
      .workspacePath,
      .projectName,
    ];

/// Paints known `{{variables}}` as tokens and unknown ones as errors, so a
/// typo shows before the runtime rejects the prompt.
class AutomationTemplateTextController extends TextEditingController {
  AutomationTemplateTextController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (withComposing && value.isComposingRangeValid) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    return TextSpan(
      style: style,
      children: <InlineSpan>[
        for (final segment in automationTemplateSegments(text))
          TextSpan(
            text: segment.text,
            style: switch (segment.known) {
              null => null,
              true => const TextStyle(
                color: AleraTokens.syntaxVariable,
                backgroundColor: AleraTokens.accentSubtle,
              ),
              false => const TextStyle(
                color: AleraTokens.error,
                decoration: TextDecoration.underline,
                decorationStyle: TextDecorationStyle.wavy,
                decorationColor: AleraTokens.error,
              ),
            },
          ),
      ],
    );
  }
}

/// The prompt field of the What step. Typing `{{` lists the variables the
/// runtime fills; Tab or Enter inserts the highlighted one. The chips below
/// insert the common ones at the caret.
class AutomationPromptEditor extends StatefulWidget {
  const AutomationPromptEditor({
    super.key,
    required this.controller,
    required this.onChanged,
    this.errorText,
    this.autofocus = false,
  });

  final AutomationTemplateTextController controller;
  final ValueChanged<String> onChanged;
  final String? errorText;
  final bool autofocus;

  @override
  State<AutomationPromptEditor> createState() => _AutomationPromptEditorState();
}

class _AutomationPromptEditorState extends State<AutomationPromptEditor> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'automationPrompt');
  AutomationVariableQuery? _query;
  List<AutomationPromptVariable> _matches = const <AutomationPromptVariable>[];
  int _highlighted = 0;
  int? _dismissedAt;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncQuery);
    _focusNode.addListener(_syncQuery);
  }

  @override
  void didUpdateWidget(AutomationPromptEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncQuery);
      widget.controller.addListener(_syncQuery);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncQuery);
    _focusNode.dispose();
    super.dispose();
  }

  void _syncQuery() {
    final value = widget.controller.value;
    final selection = value.selection;
    if (!mounted) return;
    final query =
        _focusNode.hasFocus && selection.isValid && selection.isCollapsed
        ? automationVariableQueryAt(value.text, selection.baseOffset)
        : null;
    final matches = query == null || query.start == _dismissedAt
        ? const <AutomationPromptVariable>[]
        : AutomationPromptVariable.matching(query.query);
    if (query?.start != _query?.start || query?.query != _query?.query) {
      _highlighted = 0;
    }
    if (query == null) _dismissedAt = null;
    setState(() {
      _query = query;
      _matches = matches;
    });
  }

  void _insert(AutomationPromptVariable variable) {
    final value = widget.controller.value;
    final selection = value.selection;
    final next = insertAutomationVariable(
      value.text,
      selection.isValid ? selection.start : value.text.length,
      selection.isValid ? selection.end : value.text.length,
      variable,
    );
    widget.controller.value = TextEditingValue(
      text: next.text,
      selection: TextSelection.collapsed(offset: next.caret),
    );
    widget.onChanged(next.text);
    _focusNode.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_matches.isEmpty || event is KeyUpEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        setState(() => _highlighted = (_highlighted + 1) % _matches.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        setState(
          () => _highlighted =
              (_highlighted - 1 + _matches.length) % _matches.length,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.tab:
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        if (event is KeyDownEvent) _insert(_matches[_highlighted]);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        _dismissedAt = _query?.start;
        _syncQuery();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final unknown = unknownAutomationVariables(widget.controller.text);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: AleraTextField(
            controller: widget.controller,
            focusNode: _focusNode,
            labelText: 'What Should The Agent Do?',
            hintText:
                'Review open pull requests and summarize what needs attention.',
            minLines: 5,
            maxLines: 12,
            autofocus: widget.autofocus,
            errorText: widget.errorText,
            onChanged: widget.onChanged,
          ),
        ),
        const SizedBox(height: AleraTokens.space8),
        if (_matches.isNotEmpty)
          _VariableSuggestions(
            matches: _matches,
            highlighted: _highlighted,
            onHover: (index) => setState(() => _highlighted = index),
            onSelect: _insert,
          )
        else
          Wrap(
            spacing: AleraTokens.space6,
            runSpacing: AleraTokens.space6,
            crossAxisAlignment: .center,
            children: <Widget>[
              Text('Insert Variable', style: muted),
              for (final variable in _quickVariables)
                AleraChip(
                  label: variable.label,
                  leading: AleraIcons.code,
                  tooltip: '${variable.token}\n${variable.description}',
                  onTap: () => _insert(variable),
                ),
              Text('or type {{ for more.', style: muted),
            ],
          ),
        if (unknown.isNotEmpty) ...<Widget>[
          const SizedBox(height: AleraTokens.space6),
          Text(
            '${unknown.join(', ')} ${unknown.length == 1 ? 'is not a variable' : 'are not variables'} Alera knows. Type {{ to pick one.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.error,
            ),
          ),
        ],
      ],
    );
  }
}

class const _VariableSuggestions({
  required final List<AutomationPromptVariable> matches,
  required final int highlighted,
  required final ValueChanged<int> onHover,
  required final ValueChanged<AutomationPromptVariable> onSelect,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraPanel(
      clipBehavior: .antiAlias,
      children: <Widget>[
        for (final (index, variable) in matches.indexed)
          MouseRegion(
            onEnter: (_) => onHover(index),
            child: Material(
              color: index == highlighted
                  ? AleraTokens.accentSubtle
                  : Colors.transparent,
              child: InkWell(
                canRequestFocus: false,
                onTap: () => onSelect(variable),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AleraTokens.space12,
                    vertical: AleraTokens.space6,
                  ),
                  child: Row(
                    children: <Widget>[
                      Text(
                        variable.token,
                        style: AleraTokens.monoCompactStyle.copyWith(
                          color: AleraTokens.syntaxVariable,
                        ),
                      ),
                      const SizedBox(width: AleraTokens.space12),
                      Expanded(
                        child: Text(
                          variable.description,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AleraTokens.foregroundMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space12,
            vertical: AleraTokens.space4,
          ),
          child: Text(
            'Tab or Enter inserts. Esc closes.',
            style: AleraTokens.labelMicroFaintStyle,
          ),
        ),
      ],
    );
  }
}
