import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:flutter/material.dart';

class AiAssistCustomCommandDialog extends StatefulWidget {
  const AiAssistCustomCommandDialog({super.key});

  @override
  State<AiAssistCustomCommandDialog> createState() =>
      _AiAssistCustomCommandDialogState();
}

class _AiAssistCustomCommandDialogState
    extends State<AiAssistCustomCommandDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_controller.text.trim().isNotEmpty) {
      Navigator.of(context).pop(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AleraDialog(
      maxWidth: AleraTokens.dialogCompactWidth,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Custom Command',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AleraTokens.space12),
            const Text(
              'Enter a command before selecting this agent. Use {prompt} to pass the prompt as an argument; otherwise Alera sends it on stdin.',
            ),
            const SizedBox(height: AleraTokens.space12),
            AleraTextField(
              controller: _controller,
              autofocus: true,
              labelText: 'Command',
              hintText: 'llm --system commit-message',
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AleraTokens.space16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AleraTokens.space8),
                FilledButton(
                  onPressed: _controller.text.trim().isEmpty ? null : _submit,
                  child: const Text('Use Custom Command'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
