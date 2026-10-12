import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Single-line input at [AleraTokens.controlHeight] with the same fill and
/// border as `AleraDropdownField`, so a number or time entry can sit beside a
/// dropdown in one row. [hasError] switches the border to the error token;
/// the owning field renders the message itself so the row keeps its height.
class const AleraCompactInput({
  super.key,
  required final TextEditingController controller,
  final FocusNode? focusNode,
  final String? hintText,
  final bool hasError = false,
  final bool enabled = true,
  final TextInputType? keyboardType,
  final List<TextInputFormatter>? inputFormatters,
  final ValueChanged<String>? onChanged,
  final ValueChanged<String>? onSubmitted,
  final String? semanticsLabel,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final idleBorder = hasError ? AleraTokens.error : AleraTokens.border;
    final focusedBorder = hasError ? AleraTokens.error : AleraTokens.accent;
    final field = SizedBox(
      height: AleraTokens.controlHeight,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        enabled: enabled,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textAlignVertical: TextAlignVertical.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: enabled ? AleraTokens.foreground : AleraTokens.foregroundFaint,
        ),
        cursorColor: AleraTokens.foreground,
        contextMenuBuilder: (context, editableTextState) =>
            AleraTextActionsScope.buildContextMenu(
              context,
              editableTextState,
              textActionsEnabled: false,
            ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AleraTokens.surfaceVariant,
          hintText: hintText,
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: AleraTokens.foregroundFaint,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space12,
            vertical: AleraTokens.space16,
          ),
          border: _border(idleBorder),
          enabledBorder: _border(idleBorder),
          disabledBorder: _border(AleraTokens.borderSubtle),
          focusedBorder: _border(focusedBorder),
        ),
      ),
    );
    final label = semanticsLabel;
    if (label == null) {
      return field;
    }
    return Semantics(label: label, textField: true, child: field);
  }

  OutlineInputBorder _border(Color color) => OutlineInputBorder(
    borderRadius: .circular(AleraTokens.radiusMd),
    borderSide: BorderSide(color: color),
  );
}

/// Label above and message below a compact field row, matching the label
/// style of `AleraDropdownField`.
class const AleraCompactFieldFrame({
  super.key,
  required final Widget child,
  final String? labelText,
  final String? errorText,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = labelText;
    final error = errorText;
    if (label == null && error == null) {
      return child;
    }
    return Column(
      crossAxisAlignment: .start,
      mainAxisSize: .min,
      children: <Widget>[
        if (label != null) ...<Widget>[
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(height: AleraTokens.space4),
        ],
        child,
        if (error != null && error.isNotEmpty) ...<Widget>[
          const SizedBox(height: AleraTokens.space4),
          Text(
            error,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.error,
            ),
          ),
        ],
      ],
    );
  }
}
