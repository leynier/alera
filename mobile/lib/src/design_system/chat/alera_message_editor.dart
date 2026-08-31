import 'package:flutter/material.dart';
import '../../app/theme/alera_tokens.dart';

class AleraMessageEditor extends StatefulWidget {
  const AleraMessageEditor({
    super.key,
    required this.text,
    required this.onSave,
    this.restartsHistory = false,
    this.attachmentCount = 0,
  });
  final String text;
  final Future<String?> Function(String text) onSave;
  final bool restartsHistory;
  final int attachmentCount;
  @override
  State<AleraMessageEditor> createState() => _AleraMessageEditorState();
}

class _AleraMessageEditorState extends State<AleraMessageEditor> {
  late final _input = TextEditingController(text: widget.text);
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving ||
        (_input.text.trim().isEmpty && widget.attachmentCount == 0)) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final error = await widget.onSave(_input.text);
      if (!mounted) return;
      if (error == null) {
        Navigator.of(context).pop();
        return;
      }
      setState(() => _error = error);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'The message could not be saved. Your edit is still here.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Edit Message'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _input,
              autofocus: true,
              enabled: !_saving,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'Message'),
            ),
            if (widget.attachmentCount > 0)
              Text(
                '${widget.attachmentCount} attached ${widget.attachmentCount == 1 ? 'item' : 'items'} will be preserved.',
              ),
            if (widget.restartsHistory)
              const Padding(
                padding: EdgeInsets.only(top: AleraTokens.space12),
                child: Text(
                  'Saving stops the active turn and replaces this message and all later responses. Files and actions already performed are not undone. Queued messages remain paused.',
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: AleraTokens.space8),
                child: Text(
                  _error!,
                  style: TextStyle(color: AleraTokens.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(
            _saving
                ? 'Saving'
                : widget.restartsHistory
                ? 'Save And Restart'
                : 'Save Message',
          ),
        ),
      ],
    ),
  );
}
