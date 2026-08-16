import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/ai_dictation/application/mobile_ai_dictation_settings_controller.dart';
import 'package:alera_mobile/src/features/ai_dictation/presentation/mobile_ai_dictation_control.dart';
import 'package:alera_mobile/src/features/workbench/presentation/prompt_image_insertion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Compose-mode input: type the full text, then send it. Send submits with
/// Enter; long-press Send offers sending without it.
///
/// Every trailing control is a full tap target at the shared inset, so Send
/// lines up with the mode toggle on the quick-key bar above.
class TerminalComposeBar extends ConsumerStatefulWidget {
  const TerminalComposeBar({
    super.key,
    required this.hostId,
    required this.tabId,
    required this.onSend,
    this.onPickAttachments,
  });

  final String hostId;
  final String tabId;

  /// Called with the composed text. How the text and the Enter reach the PTY is
  /// the controller's decision, not this bar's; see
  /// `terminal_compose_delivery.dart`.
  final void Function(String text, {required bool withEnter}) onSend;

  /// Resolves with the host paths to insert, or an empty list when the user
  /// backs out. Null hides the attach control, which is what an older host
  /// without any upload capability gets.
  final Future<List<String>> Function()? onPickAttachments;

  @override
  ConsumerState<TerminalComposeBar> createState() => _TerminalComposeBarState();
}

class _TerminalComposeBarState extends ConsumerState<TerminalComposeBar> {
  final TextEditingController _controller = TextEditingController();
  bool _hasText = false;
  bool _attaching = false;

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

  Future<void> _attach() async {
    final pick = widget.onPickAttachments;
    if (pick == null || _attaching) {
      return;
    }
    setState(() => _attaching = true);
    try {
      final paths = await pick();
      if (paths.isNotEmpty) {
        insertPromptImagePaths(_controller, paths);
      }
    } finally {
      if (mounted) {
        setState(() => _attaching = false);
      }
    }
  }

  Widget _action(Widget child) {
    return SizedBox.square(dimension: AleraTokens.minTapTarget, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final dictationEnabled =
        ref.watch(mobileAiDictationSettingsControllerProvider).value?.enabled ==
        true;
    final trailing = <Widget>[
      _action(
        GestureDetector(
          onLongPress: _hasText ? _sendOptions : null,
          child: IconButton.filled(
            tooltip: 'Send',
            onPressed: () => _send(withEnter: true),
            // Fills the whole tap target so the circle is exactly as tall as
            // the field beside it, instead of a 40dp glyph floating in 48dp.
            style: IconButton.styleFrom(
              minimumSize: const Size.square(AleraTokens.minTapTarget),
              padding: EdgeInsets.zero,
            ),
            icon: const Icon(Icons.arrow_upward),
          ),
        ),
      ),
    ];
    return ColoredBox(
      color: AleraTokens.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AleraTokens.terminalInputInset,
          AleraTokens.spaceXs,
          AleraTokens.terminalInputInset,
          AleraTokens.spaceSm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              // The field's own chrome is drawn here rather than through
              // InputDecoration: the decorator paints at its intrinsic height
              // and aligns to the top, so a minHeight constraint stretched the
              // hit box while still painting a 21dp sliver next to a 48dp Send.
              child: Container(
                key: const ValueKey<String>('terminal-compose-field'),
                constraints: const BoxConstraints(
                  minHeight: AleraTokens.minTapTarget,
                ),
                padding: EdgeInsets.only(
                  // An in-field control supplies the inset on its own side, so
                  // it hugs the field edge instead of floating inside it.
                  left: widget.onPickAttachments == null
                      ? AleraTokens.spaceMd
                      : AleraTokens.spaceXs,
                  right: dictationEnabled && !_hasText
                      ? 0
                      : AleraTokens.spaceMd,
                ),
                decoration: BoxDecoration(
                  color: AleraTokens.surfaceElevated,
                  borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                  border: Border.all(color: AleraTokens.borderSubtle),
                ),
                child: Row(
                  // Pinned to the first line: a growing field pushes text down,
                  // not the controls.
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (widget.onPickAttachments != null)
                      SizedBox(
                        // Narrower than a full tap target so it costs the text
                        // as little width as possible, but still the full
                        // height, which is where the thumb actually lands.
                        width: AleraTokens.space32,
                        height: AleraTokens.minTapTarget,
                        child: IconButton(
                          tooltip: 'Add Attachment',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: AleraTokens.space32,
                            minHeight: AleraTokens.minTapTarget,
                          ),
                          onPressed: _attaching ? null : _attach,
                          icon: _attaching
                              ? const SizedBox.square(
                                  dimension: AleraTokens.spaceLg,
                                  child: CircularProgressIndicator(
                                    strokeWidth: AleraTokens.strokeSm,
                                  ),
                                )
                              : const Icon(
                                  Icons.add,
                                  size: AleraTokens.space20,
                                ),
                        ),
                      ),
                    Expanded(
                      // One line centres against the buttons; more lines grow
                      // downward while the buttons stay on the first line.
                      child: Container(
                        constraints: const BoxConstraints(
                          minHeight: AleraTokens.minTapTarget,
                        ),
                        alignment: Alignment.centerLeft,
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: AleraTokens.composeBarMaxLines,
                          autocorrect: true,
                          enableSuggestions: true,
                          textInputAction: TextInputAction.newline,
                          style: const TextStyle(
                            fontFamily: AleraTokens.monoFontFamily,
                          ),
                          // Every border and the fill are cleared, not just `border`:
                          // the app's inputDecorationTheme sets `filled` and its own
                          // enabled/focused borders, which would paint a second boxed
                          // card inside the one above.
                          decoration: const InputDecoration(
                            hintText: 'Type a command',
                            filled: false,
                            isCollapsed: true,
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    // Dictation is for starting a message, not editing one:
                    // the first typed character gives the space back to text.
                    if (dictationEnabled && !_hasText)
                      SizedBox.square(
                        dimension: AleraTokens.minTapTarget,
                        child: MobileAiDictationControl(
                          hostId: widget.hostId,
                          targetKey: 'terminal-${widget.tabId}',
                          tabId: widget.tabId,
                          controller: _controller,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            for (final action in trailing) ...<Widget>[
              const SizedBox(width: AleraTokens.terminalInputInset),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
