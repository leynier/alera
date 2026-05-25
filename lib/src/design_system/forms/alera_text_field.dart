import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Styled text input.
///
/// - Default ([dense] == false): relies on the global `inputDecorationTheme`
///   (the standard surface-variant field used in dialogs and settings).
/// - [dense] == true: the compact, surface-filled variant used inside the
///   narrow sidebar, where the field must contrast against a surface-variant
///   background.
class AleraTextField extends StatelessWidget {
  const AleraTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.prefixIcon,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.dense = false,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final IconData? prefixIcon;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final bool dense;

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
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          hintText: hintText,
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
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textAlignVertical: TextAlignVertical.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AleraTokens.foreground,
        ),
        cursorColor: AleraTokens.foreground,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AleraTokens.surface,
          hintText: hintText,
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
