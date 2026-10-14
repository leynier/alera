import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/forms/alera_text_field.dart';
import 'package:alera_mobile/src/design_system/layout/alera_dialog.dart';
import 'package:flutter/material.dart';

/// Asks for a new secret value. Write-only: the current value is never
/// shown, because the host never sends it back, and the field never offers
/// suggestions or autocorrect. Returns the value, or null when cancelled.
Future<String?> showAgentProviderSecretDialog(
  BuildContext context, {
  required String name,
  required bool replacing,
}) => showDialog<String>(
  context: context,
  builder: (context) => _SecretDialog(name: name, replacing: replacing),
);

class const _SecretDialog({
  required final String name,
  required final bool replacing,
}) extends StatefulWidget {
  @override
  State<_SecretDialog> createState() => _SecretDialogState();
}

class _SecretDialogState extends State<_SecretDialog> {
  final TextEditingController _value = TextEditingController();

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _save() {
    final value = _value.text;
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: AleraTokens.emptyStateMaxWidth,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          spacing: AleraTokens.space12,
          children: <Widget>[
            Text(
              widget.replacing ? 'Replace Secret' : 'Set Secret',
              style: theme.textTheme.titleMedium,
            ),
            Text(
              'Saved on the host only. Alera never shows it again.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
            AleraTextField(
              controller: _value,
              labelText: widget.name,
              autofocus: true,
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
            ),
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
                    onPressed: _value.text.isEmpty ? null : _save,
                    child: const Text('Save'),
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
