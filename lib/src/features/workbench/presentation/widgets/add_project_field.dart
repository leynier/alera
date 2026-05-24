import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Text input used in the view-options modal to filter the list of available
/// projects. Pressing Enter forwards the trimmed text to [onSubmit] so the
/// modal can pick the first matching project and add it to the selection.
///
/// Visually mirrors [SidebarSearchBar] — same height, radius, border colors
/// and density — so the modal feels coherent with the sidebar search bar.
class AddProjectField extends StatelessWidget {
  const AddProjectField({
    super.key,
    required this.controller,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: AleraTokens.space32 + AleraTokens.space8,
      child: TextField(
        controller: controller,
        onSubmitted: onSubmit,
        textAlignVertical: TextAlignVertical.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: AleraTokens.foreground,
        ),
        cursorColor: AleraTokens.foreground,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: AleraTokens.surface,
          hintText: 'Add project…',
          hintStyle: theme.textTheme.bodySmall?.copyWith(
            color: AleraTokens.foregroundFaint,
          ),
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: AleraTokens.space8, right: 4),
            child: Icon(
              Icons.add,
              size: 14,
              color: AleraTokens.foregroundFaint,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 24,
            minHeight: AleraTokens.space32 + AleraTokens.space8,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            borderSide: const BorderSide(color: AleraTokens.borderSubtle),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            borderSide: const BorderSide(color: AleraTokens.borderSubtle),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            borderSide: const BorderSide(color: AleraTokens.border),
          ),
        ),
      ),
    );
  }
}
