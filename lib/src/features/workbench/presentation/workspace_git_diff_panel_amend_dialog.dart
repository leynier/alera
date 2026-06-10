part of 'workspace_git_diff_panel.dart';

class _AmendCommitDialog extends StatefulWidget {
  const _AmendCommitDialog({required this.initialMessage});

  final String initialMessage;

  @override
  State<_AmendCommitDialog> createState() => _AmendCommitDialogState();
}

class _AmendCommitDialogState extends State<_AmendCommitDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialMessage);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final message = _controller.text.trim();
    if (message.isEmpty) {
      setState(() => _errorText = 'Message Is Required');
      return;
    }
    Navigator.of(context).pop(message);
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
            Text('Amend Commit', style: theme.textTheme.titleMedium),
            const SizedBox(height: AleraTokens.space16),
            TextField(
              controller: _controller,
              autofocus: true,
              minLines: 4,
              maxLines: 8,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.foreground,
              ),
              cursorColor: AleraTokens.foreground,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: AleraTokens.surface,
                hintText: 'Message',
                hintStyle: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundFaint,
                ),
                errorText: _errorText,
                contentPadding: const EdgeInsets.fromLTRB(
                  AleraTokens.space12,
                  AleraTokens.space12,
                  AleraTokens.space12,
                  AleraTokens.space12,
                ),
              ),
              onChanged: (_) {
                if (_errorText != null) {
                  setState(() => _errorText = null);
                }
              },
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
                FilledButton(onPressed: _submit, child: const Text('Amend')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
