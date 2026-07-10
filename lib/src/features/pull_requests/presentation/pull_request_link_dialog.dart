import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:flutter/material.dart';

/// Prompts for a review reference (`#123` or a URL). Returns the raw string, or
/// null when cancelled.
Future<String?> showLinkReviewDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const _LinkReviewDialog(),
  );
}

class _LinkReviewDialog extends StatefulWidget {
  const _LinkReviewDialog();

  @override
  State<_LinkReviewDialog> createState() => _LinkReviewDialogState();
}

class _LinkReviewDialogState extends State<_LinkReviewDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _errorText = 'Enter A PR Number Or URL');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 460,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Link Pull Request', style: theme.textTheme.titleMedium),
            const SizedBox(height: AleraTokens.space16),
            TextField(
              controller: _controller,
              autofocus: true,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foreground,
              ),
              cursorColor: AleraTokens.foreground,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: AleraTokens.surface,
                hintText: '#123 Or Pull Request URL',
                hintStyle: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundFaint,
                ),
                errorText: _errorText,
                contentPadding: const EdgeInsets.all(AleraTokens.space12),
              ),
              onChanged: (_) {
                if (_errorText != null) {
                  setState(() => _errorText = null);
                }
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AleraTokens.space20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AleraTokens.space8),
                FilledButton(onPressed: _submit, child: const Text('Link')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
