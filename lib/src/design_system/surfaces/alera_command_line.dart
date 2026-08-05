import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/menus/alera_text_selection_toolbar.dart';
import 'package:flutter/material.dart';

/// A shell command shown verbatim, selectable, with room for the action that
/// runs or copies it.
///
/// Selectable rather than plain text because the command is often the thing a
/// user wants to take somewhere else, and a copy button is no help when they
/// need only part of it.
class AleraCommandLine extends StatelessWidget {
  const AleraCommandLine({
    super.key,
    required this.command,
    this.trailing,
    this.backgroundColor = AleraTokens.surface,
    this.singleLine = false,
  });

  final String command;

  /// Action slot, rendered after the command. Typically a run or copy button.
  final Widget? trailing;

  /// Overridable so the component reads as inset against either surface tone.
  final Color backgroundColor;

  /// Keeps long commands on one row and lets the user scroll horizontally.
  final bool singleLine;

  @override
  Widget build(BuildContext context) {
    final commandText = SelectableText(
      command,
      maxLines: singleLine ? 1 : null,
      contextMenuBuilder: AleraTextSelectionToolbar.editableText,
      style: AleraTokens.monoStyle.copyWith(color: AleraTokens.foreground),
    );
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      padding: const EdgeInsets.all(AleraTokens.space12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: singleLine
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: commandText,
                  )
                : commandText,
          ),
          if (trailing case final action?) ...<Widget>[
            const SizedBox(width: AleraTokens.space8),
            action,
          ],
        ],
      ),
    );
  }
}
