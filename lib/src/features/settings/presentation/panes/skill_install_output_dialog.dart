import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/design_system/menus/alera_text_selection_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Full, selectable installer output. The settings row can only show a single
/// line, and the line that names an installer failure is rarely the first one.
class const SkillInstallOutputDialog({
  super.key,
  required final String title,
  required final String output,
}) extends StatelessWidget {
  static Future<void> show(
    BuildContext context, {
    required String title,
    required String output,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) =>
          SkillInstallOutputDialog(title: title, output: output),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AleraDialog(
      maxWidth: AleraTokens.dialogWideWidth,
      maxHeight: AleraTokens.dialogWideWidth,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space16),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            AleraDialogHeader(
              title: title,
              onClose: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: AleraTokens.space12),
            Flexible(
              child: Container(
                width: .infinity,
                padding: const EdgeInsets.all(AleraTokens.space12),
                decoration: BoxDecoration(
                  color: AleraTokens.surfaceVariant,
                  borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
                  border: Border.all(color: AleraTokens.borderSubtle),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    output,
                    contextMenuBuilder: AleraTextSelectionToolbar.editableText,
                    style: AleraTokens.monoStyle.copyWith(
                      color: AleraTokens.foreground,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AleraTokens.space12),
            Row(
              mainAxisAlignment: .end,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: output)),
                  icon: const Icon(AleraIcons.copy, size: 16),
                  label: const Text('Copy Output'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
