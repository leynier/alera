import 'package:alera/src/app/theme/alera_tokens.dart';
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
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.onTap,
    this.autofocus = false,
    this.dense = false,
    this.fillColor,
    this.readOnly = false,
    this.enabled,
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
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onEditingComplete;
  final VoidCallback? onTap;
  final bool autofocus;
  final bool dense;

  /// Dense fill color. Defaults to [AleraTokens.surface].
  final Color? fillColor;
  final bool readOnly;
  final bool? enabled;

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
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        onEditingComplete: onEditingComplete,
        onTap: onTap,
        readOnly: readOnly,
        enabled: enabled,
        decoration: InputDecoration(
          labelText: labelText,
          hintText: hintText,
          errorText: errorText,
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
        inputFormatters: inputFormatters,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        onEditingComplete: onEditingComplete,
        onTap: onTap,
        readOnly: readOnly,
        enabled: enabled,
        textAlignVertical: TextAlignVertical.center,
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
