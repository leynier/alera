import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/hover_container.dart';
import 'package:flutter/material.dart';

/// One row of a question's answer list: a numbered circle, or an [icon] for
/// rows that are not options, then the label and an optional description.
/// Hover reveals a chevron on rows that answer when clicked ([advances]); a
/// [selected] row keeps its highlight and shows a check.
class const AgentChatQuestionOptionRow({
  super.key,
  required final String label,
  required final VoidCallback? onTap,
  final int? number,
  final IconData? icon,
  final String description = '',
  final bool selected = false,
  final bool advances = true,
  final bool muted = false,
}) extends StatefulWidget {
  @override
  State<AgentChatQuestionOptionRow> createState() =>
      _AgentChatQuestionOptionRowState();
}

class _AgentChatQuestionOptionRowState
    extends State<AgentChatQuestionOptionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final interactive = widget.onTap != null;
    final restingColor = widget.selected
        ? AleraTokens.accentSubtle
        : Colors.transparent;
    final description = widget.description.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Semantics(
          selected: widget.selected,
          child: HoverContainer(
            onTap: widget.onTap,
            baseColor: restingColor,
            hoverColor: interactive ? AleraTokens.accentSubtle : restingColor,
            borderRadius: AleraTokens.radiusLg,
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space8,
              vertical: AleraTokens.space6,
            ),
            child: Opacity(
              opacity: interactive ? 1 : AleraTokens.disabledOpacity,
              child: Row(
                children: <Widget>[
                  AgentChatQuestionMarker(
                    number: widget.number,
                    icon: widget.icon,
                    selected: widget.selected,
                  ),
                  const SizedBox(width: AleraTokens.space12),
                  Expanded(
                    child: Column(
                      mainAxisSize: .min,
                      crossAxisAlignment: .start,
                      children: <Widget>[
                        Text(
                          widget.label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: widget.muted
                                ? AleraTokens.foregroundMuted
                                : AleraTokens.foreground,
                            fontWeight: widget.muted ? .w400 : .w500,
                          ),
                        ),
                        if (description.isNotEmpty) ...<Widget>[
                          const SizedBox(height: AleraTokens.space2),
                          Text(
                            description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AleraTokens.foregroundMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  if (widget.selected)
                    const Icon(
                      AleraIcons.check,
                      size: AleraTokens.iconMd,
                      color: AleraTokens.foreground,
                    )
                  else
                    Visibility(
                      visible: interactive && widget.advances && _hovered,
                      maintainAnimation: true,
                      maintainSize: true,
                      maintainState: true,
                      child: const Icon(
                        AleraIcons.chevronRight,
                        size: AleraTokens.iconMd,
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The circle at the start of a question row: the option's number, or an
/// icon for the free-text answer. Filled while the option is selected.
class const AgentChatQuestionMarker({
  super.key,
  final int? number,
  final IconData? icon,
  final bool selected = false,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: AleraTokens.space24,
      height: AleraTokens.space24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: .circle,
        color: selected ? AleraTokens.accent : null,
        border: Border.all(
          color: selected ? AleraTokens.accent : AleraTokens.border,
        ),
      ),
      child: icon != null
          ? Icon(
              icon,
              size: AleraTokens.iconSm,
              color: AleraTokens.foregroundMuted,
            )
          : Text(
              number == null ? '' : '$number',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected
                    ? AleraTokens.onAccent
                    : AleraTokens.foregroundMuted,
              ),
            ),
    );
  }
}

/// Free-text answer of a question. Enter answers through [onEnter]; Shift+Enter
/// starts a new line, except in a [secret] answer, which stays on one line.
/// [showMarker] lines the field up with the option rows above it.
class const AgentChatQuestionAnswerField({
  super.key,
  required final TextEditingController controller,
  required final FocusNode focusNode,
  required final bool enabled,
  required final bool secret,
  required final ValueChanged<String> onChanged,
  required final VoidCallback onEnter,
  final bool showMarker = false,
  final bool autofocus = false,
}) extends StatelessWidget {
  static const int _maxLines = 5;

  void _insertLineBreak() {
    if (!enabled) return;
    final value = controller.value;
    final selection = value.selection;
    final start = selection.start < 0 ? value.text.length : selection.start;
    final end = selection.end < 0 ? value.text.length : selection.end;
    controller.value = value.copyWith(
      text: value.text.replaceRange(start, end, '\n'),
      selection: .collapsed(offset: start + 1),
      composing: .empty,
    );
    onChanged(controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final field = CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(.enter, includeRepeats: false): onEnter,
        const SingleActivator(.numpadEnter, includeRepeats: false): onEnter,
        if (!secret)
          const SingleActivator(.enter, shift: true): _insertLineBreak,
      },
      child: AleraTextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        enabled: enabled,
        obscureText: secret,
        enableSuggestions: !secret,
        autocorrect: !secret,
        minLines: 1,
        maxLines: secret ? 1 : _maxLines,
        hintText: 'Type your answer',
        onChanged: onChanged,
        onSubmitted: (_) => onEnter(),
        onCommandEnter: onEnter,
      ),
    );
    if (!showMarker) return field;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space8,
        vertical: AleraTokens.space4,
      ),
      child: Row(
        children: <Widget>[
          const AgentChatQuestionMarker(icon: AleraIcons.edit),
          const SizedBox(width: AleraTokens.space12),
          Expanded(child: field),
        ],
      ),
    );
  }
}
