import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
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
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: widget.labelText,
          helperText: widget.helperText,
          helperMaxLines: 2,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Rename')),
      ],
      actionsPadding: const EdgeInsets.fromLTRB(
        AleraTokens.spaceLg,
        0,
        AleraTokens.spaceLg,
        AleraTokens.spaceLg,
      ),
    );
  }
}
