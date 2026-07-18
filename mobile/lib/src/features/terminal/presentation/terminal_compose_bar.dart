import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';

/// Compose-mode input: type the full text, then send it as one write. Send
/// appends a newline; long-press Send offers sending without one.
class TerminalComposeBar extends StatefulWidget {
  const TerminalComposeBar({super.key, required this.onSend});

  /// Called with the composed text; [withNewline] appends `\n`.
  final void Function(String text, {required bool withNewline}) onSend;

  @override
  State<TerminalComposeBar> createState() => _TerminalComposeBarState();
}

class _TerminalComposeBarState extends State<TerminalComposeBar> {
  final TextEditingController _controller = TextEditingController();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.isNotEmpty;
      if (hasText != _hasText) {
        setState(() {
          _hasText = hasText;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send({required bool withNewline}) {
    final text = _controller.text;
    if (text.isEmpty && withNewline) {
      // An empty send still means "press Enter" in a terminal.
      widget.onSend('', withNewline: true);
      return;
    }
    if (text.isEmpty) {
      return;
    }
    widget.onSend(text, withNewline: withNewline);
    _controller.clear();
  }

  Future<void> _sendOptions() async {
    final withNewline = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.keyboard_return),
              title: const Text('Send With Newline'),
              onTap: () => Navigator.of(context).pop(true),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('Send Without Newline'),
              onTap: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
    if (withNewline != null) {
      _send(withNewline: withNewline);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AleraTokens.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AleraTokens.spaceMd,
          AleraTokens.spaceXs,
          AleraTokens.spaceXs,
          AleraTokens.spaceSm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: AleraTokens.composeBarMaxLines,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(fontFamily: AleraTokens.monoFontFamily),
                decoration: const InputDecoration(
                  hintText: 'Type A Command',
                  isDense: true,
                ),
                onSubmitted: (_) => _send(withNewline: true),
              ),
            ),
            const SizedBox(width: AleraTokens.spaceXs),
            GestureDetector(
              onLongPress: _hasText ? _sendOptions : null,
              child: IconButton.filled(
                tooltip: 'Send',
                onPressed: () => _send(withNewline: true),
                icon: const Icon(Icons.send),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
