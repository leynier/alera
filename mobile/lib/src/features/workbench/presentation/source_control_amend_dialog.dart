import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/layout/alera_dialog.dart';
import 'package:flutter/material.dart';

/// Edits the message of the commit being amended, pre-filled with the current
/// HEAD message. Pops the trimmed message, or null when cancelled.
class const SourceControlAmendDialog({
  super.key,
  required final String initialMessage,
}) extends StatefulWidget {
  @override
  State<SourceControlAmendDialog> createState() =>
      _SourceControlAmendDialogState();
}

class _SourceControlAmendDialogState extends State<SourceControlAmendDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialMessage,
  );
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final message = _controller.text.trim();
    if (message.isEmpty) {
      setState(() => _errorText = 'Message is required');
      return;
    }
    Navigator.of(context).pop(message);
  }

  @override
  Widget build(BuildContext context) {
    return AleraDialog(
      maxWidth: 420,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            Text(
              'Amend Commit',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AleraTokens.space12),
            AleraTextField(
              controller: _controller,
              autofocus: true,
              hintText: 'Message',
              errorText: _errorText,
              minLines: 3,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              onChanged: (_) {
                if (_errorText != null) {
                  setState(() => _errorText = null);
                }
              },
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
                    child: const Text('Amend'),
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
