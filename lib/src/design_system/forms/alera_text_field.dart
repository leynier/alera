import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_clipboard_paste_action.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Styled text input.
///
/// - Default ([dense] == false): relies on the global `inputDecorationTheme`
///   (the standard surface-variant field used in dialogs and settings).
/// - [dense] == true: the compact filled variant. Defaults to a surface fill
///   for surface-variant backgrounds (sidebars). On a surface chrome bar,
///   pass [fillColor] as [AleraTokens.surfaceVariant] so the field still
///   contrasts.
class AleraTextField extends StatelessWidget {
  const AleraTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.labelText,
    this.hintText,
    this.errorText,
    this.prefixIcon,
    this.suffix,
    this.keyboardType,
    this.inputFormatters,
    this.textAlignVertical,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.onTap,
    this.onPaste,
    this.autofocus = false,
    this.dense = false,
    this.denseHeight = defaultDenseHeight,
    this.fillColor,
    this.readOnly = false,
    this.enabled,
    this.obscureText = false,
    this.enableSuggestions = true,
    this.autocorrect = true,
    this.textActionsEnabled = true,
    this.minLines,
    this.maxLines = 1,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? labelText;
  final String? hintText;
  final String? errorText;
  final IconData? prefixIcon;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextAlignVertical? textAlignVertical;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onEditingComplete;
  final VoidCallback? onTap;

  /// Handles a paste before the default text action runs.
  ///
  /// Return `true` when the callback consumed the clipboard. Returning
  /// `false` preserves Flutter's normal text-paste behavior.
  final Future<bool> Function()? onPaste;
  final bool autofocus;
  final bool dense;
  final double denseHeight;

  /// Dense fill color. Defaults to [AleraTokens.surface].
  final Color? fillColor;
  final bool readOnly;
  final bool? enabled;
  final bool obscureText;
  final bool enableSuggestions;
  final bool autocorrect;

  /// Keeps this field's native editing menu without the Text Actions entry.
  final bool textActionsEnabled;

  final int? minLines;
  final int? maxLines;

  /// Default height of the dense variant: `space32 + space8`.
  static const double defaultDenseHeight =
      AleraTokens.space32 + AleraTokens.space8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textActionsAvailable =
        textActionsEnabled &&
        AleraTextActionsScope.maybeOf(context)?.enabled == true;
    final contextMenuBuilder = onPaste != null || textActionsAvailable
        ? _buildContextMenu
        : null;
    if (!dense) {
      final field = TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        textAlignVertical: textAlignVertical,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        onEditingComplete: onEditingComplete,
        onTap: onTap,
        contextMenuBuilder: contextMenuBuilder,
        readOnly: readOnly,
        enabled: enabled,
        obscureText: obscureText,
        enableSuggestions: enableSuggestions,
        autocorrect: autocorrect,
        minLines: minLines,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: labelText,
          hintText: hintText,
          errorText: errorText,
          prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 16),
          suffixIcon: suffix,
        ),
      );
      return _withPasteAction(field);
    }

    final field = SizedBox(
      height: denseHeight,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        onEditingComplete: onEditingComplete,
        onTap: onTap,
        contextMenuBuilder: contextMenuBuilder,
        readOnly: readOnly,
        enabled: enabled,
        obscureText: obscureText,
        enableSuggestions: enableSuggestions,
        autocorrect: autocorrect,
        minLines: minLines,
        maxLines: maxLines,
        textAlignVertical: textAlignVertical ?? TextAlignVertical.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AleraTokens.foreground,
        ),
        cursorColor: AleraTokens.foreground,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: fillColor ?? AleraTokens.surface,
          labelText: labelText,
          hintText: hintText,
          errorText: errorText,
          hintStyle: theme.textTheme.bodySmall?.copyWith(
            color: AleraTokens.foregroundFaint,
          ),
          prefixIcon: prefixIcon == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(
                    left: AleraTokens.space8,
                    right: 4,
                  ),
                  child: Icon(
                    prefixIcon,
                    size: 14,
                    color: AleraTokens.foregroundFaint,
                  ),
                ),
          prefixIconConstraints: BoxConstraints(
            minWidth: AleraTokens.space24,
            minHeight: denseHeight,
          ),
          suffixIcon: suffix,
          suffixIconConstraints: BoxConstraints(
            minWidth: AleraTokens.space24,
            minHeight: denseHeight,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space16,
          ),
          border: _denseBorder(AleraTokens.borderSubtle),
          enabledBorder: _denseBorder(AleraTokens.borderSubtle),
          focusedBorder: _denseBorder(AleraTokens.border),
        ),
      ),
    );
    return _withPasteAction(field);
  }

  Widget _withPasteAction(Widget field) {
    final paste = onPaste;
    if (paste == null) {
      return field;
    }
    return Actions(
      actions: <Type, Action<Intent>>{
        PasteTextIntent: AleraClipboardPasteAction(paste),
      },
      child: field,
    );
  }

  Widget _buildContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
  ) {
    return AleraTextActionsScope.buildContextMenu(
      context,
      editableTextState,
      onPaste: onPaste,
      textActionsEnabled: textActionsEnabled,
    );
  }

  OutlineInputBorder _denseBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
    borderSide: BorderSide(color: color),
  );
}
