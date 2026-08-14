import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/ai_dictation/presentation/mobile_ai_dictation_control.dart';
import 'package:flutter/material.dart';

/// Compose-mode input: type the full text, then send it. Send submits with
/// Enter; long-press Send offers sending without it.
class TerminalComposeBar extends StatefulWidget {
  const TerminalComposeBar({
    super.key,
    required this.hostId,
    required this.tabId,
    required this.onSend,
  });

  final String hostId;
  final String tabId;

  /// Called with the composed text. How the text and the Enter reach the PTY is
  /// the controller's decision, not this bar's; see
  /// `terminal_compose_delivery.dart`.
  final void Function(String text, {required bool withEnter}) onSend;

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

  void _send({required bool withEnter}) {
    final text = _controller.text;
    if (text.isEmpty && withEnter) {
      // An empty send still means "press Enter" in a terminal.
      widget.onSend('', withEnter: true);
      return;
    }
    if (text.isEmpty) {
      return;
    }
    widget.onSend(text, withEnter: withEnter);
    _controller.clear();
  }

  Future<void> _sendOptions() async {
    final withEnter = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.keyboard_return),
              title: const Text('Send With Enter'),
              onTap: () => Navigator.of(context).pop(true),
            ),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('Send Without Enter'),
              onTap: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      ),
    );
    if (withEnter != null) {
      _send(withEnter: withEnter);
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
                autocorrect: true,
                enableSuggestions: true,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(fontFamily: AleraTokens.monoFontFamily),
                decoration: const InputDecoration(
                  hintText: 'Type A Command',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: AleraTokens.spaceXs),
            MobileAiDictationControl(
              hostId: widget.hostId,
              targetKey: 'terminal-${widget.tabId}',
              tabId: widget.tabId,
              controller: _controller,
            ),
            GestureDetector(
              onLongPress: _hasText ? _sendOptions : null,
              child: IconButton.filled(
                tooltip: 'Send',
                onPressed: () => _send(withEnter: true),
                icon: const Icon(Icons.arrow_upward),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
