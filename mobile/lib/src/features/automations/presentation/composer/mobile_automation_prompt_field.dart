import 'package:alera_automations/alera_automations.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/chips/alera_chip.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';

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
class MobileAutomationTemplateTextController extends TextEditingController {
  MobileAutomationTemplateTextController({super.text});

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
                color: AleraTokens.info,
                backgroundColor: AleraTokens.accentSubtle,
              ),
              false => const TextStyle(
                color: AleraTokens.error,
                decoration: TextDecoration.underline,
                decorationColor: AleraTokens.error,
              ),
            },
          ),
      ],
    );
  }
}

/// The prompt of the composer. The chips insert the common variables at the
/// caret; typing `{{` swaps them for every variable that matches.
class MobileAutomationPromptField extends StatefulWidget {
  const MobileAutomationPromptField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.errorText,
  });

  final MobileAutomationTemplateTextController controller;
  final ValueChanged<String> onChanged;
  final String? errorText;

  @override
  State<MobileAutomationPromptField> createState() =>
      _MobileAutomationPromptFieldState();
}

class _MobileAutomationPromptFieldState
    extends State<MobileAutomationPromptField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _insert(AutomationPromptVariable variable) {
    final value = widget.controller.value;
    final selection = value.selection;
    final end = selection.isValid ? selection.end : value.text.length;
    final start = selection.isValid ? selection.start : end;
    final inserted = insertAutomationVariable(value.text, start, end, variable);
    widget.controller.value = TextEditingValue(
      text: inserted.text,
      selection: TextSelection.collapsed(offset: inserted.caret),
    );
    widget.onChanged(inserted.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final value = widget.controller.value;
    final caret = value.selection.isValid && value.selection.isCollapsed
        ? value.selection.baseOffset
        : -1;
    final query = caret < 0
        ? null
        : automationVariableQueryAt(value.text, caret);
    final variables = query == null
        ? _quickVariables
        : AutomationPromptVariable.matching(query.query);
    final unknown = <String>{
      for (final segment in automationTemplateSegments(value.text))
        if (segment.known == false) segment.text,
    };
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        AleraTextField(
          controller: widget.controller,
          labelText: 'Prompt',
          hintText: 'What should the agent do? For example, review open pull requests and summarize what needs attention.',
          minLines: 6,
          maxLines: 12,
          errorText: widget.errorText,
          onChanged: widget.onChanged,
        ),
        const SizedBox(height: AleraTokens.spaceSm),
        Text(
          query == null
              ? 'Insert a variable, or type {{ for more:'
              : 'Variables matching {{${query.query}:',
          style: muted,
        ),
        const SizedBox(height: AleraTokens.spaceXs),
        Wrap(
          spacing: AleraTokens.spaceSm,
          runSpacing: AleraTokens.spaceSm,
          children: <Widget>[
            for (final variable in variables)
              AleraChip(
                label: variable.label,
                leading: AleraIcons.code,
                tooltip: '${variable.token}\n${variable.description}',
                onTap: () => _insert(variable),
              ),
          ],
        ),
        if (unknown.isNotEmpty) ...<Widget>[
          const SizedBox(height: AleraTokens.spaceXs),
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
