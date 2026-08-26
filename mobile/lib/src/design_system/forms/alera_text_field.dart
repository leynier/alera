import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Styled text input.
///
/// - Default ([dense] == false): relies on the global `inputDecorationTheme`.
/// - [dense] == true: compact surface-filled variant for narrow toolbars.
class AleraTextField extends StatelessWidget {
  const AleraTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.labelText,
    this.hintText,
    this.errorText,
    this.helperText,
    this.prefixIcon,
    this.suffix,
    this.keyboardType,
    this.minLines,
    this.maxLines = 1,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.onTap,
    this.autofocus = false,
    this.dense = false,
    this.readOnly = false,
    this.enabled,
    this.obscureText = false,
    this.enableSuggestions = true,
    this.autocorrect = true,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? labelText;
  final String? hintText;
  final String? errorText;
  final String? helperText;
  final IconData? prefixIcon;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final int? minLines;
  final int? maxLines;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onEditingComplete;
  final VoidCallback? onTap;
  final bool autofocus;
  final bool dense;
  final bool readOnly;
  final bool? enabled;
  final bool obscureText;
  final bool enableSuggestions;
  final bool autocorrect;

  /// Fixed height of the dense variant: `space32 + space8`.
  static const double denseHeight = AleraTokens.space32 + AleraTokens.space8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!dense) {
      return TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        keyboardType: keyboardType,
        minLines: minLines,
        maxLines: maxLines,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        onEditingComplete: onEditingComplete,
        onTap: onTap,
        readOnly: readOnly,
        enabled: enabled,
        obscureText: obscureText,
        enableSuggestions: enableSuggestions,
        autocorrect: autocorrect,
        decoration: InputDecoration(
          labelText: labelText,
          hintText: hintText,
          errorText: errorText,
          helperText: helperText,
          helperMaxLines: 2,
          prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 16),
          suffixIcon: suffix,
        ),
      );
    }

    return SizedBox(
      height: denseHeight,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        keyboardType: keyboardType,
        minLines: minLines,
        maxLines: maxLines,
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        onEditingComplete: onEditingComplete,
        onTap: onTap,
        readOnly: readOnly,
        enabled: enabled,
        obscureText: obscureText,
        enableSuggestions: enableSuggestions,
        autocorrect: autocorrect,
        textAlignVertical: TextAlignVertical.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AleraTokens.foreground,
        ),
        cursorColor: AleraTokens.foreground,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AleraTokens.surface,
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
          prefixIconConstraints: const BoxConstraints(
            minWidth: 24,
            minHeight: denseHeight,
          ),
          suffixIcon: suffix,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 24,
            minHeight: denseHeight,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
          ),
          border: _denseBorder(AleraTokens.borderSubtle),
          enabledBorder: _denseBorder(AleraTokens.borderSubtle),
          focusedBorder: _denseBorder(AleraTokens.border),
        ),
      ),
    );
  }

  OutlineInputBorder _denseBorder(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
    borderSide: BorderSide(color: color),
  );
}
