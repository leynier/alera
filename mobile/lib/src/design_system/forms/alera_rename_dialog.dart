import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/layout/alera_dialog.dart';
import 'package:flutter/material.dart';

/// Prompts for a new name and pops with the trimmed value. When [allowEmpty]
/// is true an empty submission pops with an empty string so callers can treat
/// it as "clear the override"; otherwise empty input keeps the dialog open.
class AleraRenameDialog extends StatefulWidget {
  const AleraRenameDialog({
    super.key,
    required this.title,
    required this.labelText,
    this.initialValue = '',
    this.helperText,
    this.allowEmpty = false,
  });

  final String title;
  final String labelText;
  final String initialValue;
  final String? helperText;
  final bool allowEmpty;

  @override
  State<AleraRenameDialog> createState() => _AleraRenameDialogState();
}

class _AleraRenameDialogState extends State<AleraRenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty && !widget.allowEmpty) {
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 420,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AleraTokens.space12),
            AleraTextField(
              controller: _controller,
              autofocus: true,
              labelText: widget.labelText,
              helperText: widget.helperText,
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AleraTokens.space20),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    child: const Text('Rename'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
