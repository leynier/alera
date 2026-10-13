import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Long enough to read the check mark, short enough to copy again right away.
const Duration _copiedFeedbackDuration = Duration(seconds: 2);

/// Read-only block of monospaced [code]: a header with the [language] label
/// and a Copy button revealed on hover, over a body that scrolls sideways
/// instead of wrapping.
///
/// [highlighted] replaces the plain [code] span (syntax colors, for example)
/// and is drawn over the mono base style. The body is a plain [Text.rich]
/// rather than a selectable text, so one ancestor `SelectionArea` can select
/// across it and the text around it. The header is omitted when there is no
/// [language] and [showCopy] is off.
class const AleraCodeBlock({
  super.key,
  required final String code,
  final String language = '',
  final InlineSpan? highlighted,
  final bool showCopy = true,
}) extends StatefulWidget {
  @override
  State<AleraCodeBlock> createState() => _AleraCodeBlockState();
}

class _AleraCodeBlockState extends State<AleraCodeBlock> {
  // Hover only fades the Copy button, so it stays out of setState: a long
  // code body is not rebuilt each time the pointer crosses the block.
  final ValueNotifier<bool> _hovered = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _hovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = widget.language.trim();
    final showHeader = language.isNotEmpty || widget.showCopy;
    return MouseRegion(
      onEnter: (_) => _hovered.value = true,
      onExit: (_) => _hovered.value = false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AleraTokens.bg,
          border: Border.all(color: AleraTokens.borderSubtle),
          borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        ),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: <Widget>[
            if (showHeader) ...<Widget>[
              // Selecting a whole message should copy the code, not the label.
              SelectionContainer.disabled(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AleraTokens.space12,
                    AleraTokens.space2,
                    AleraTokens.space4,
                    AleraTokens.space2,
                  ),
                  child: SizedBox(
                    height: AleraTokens.iconButtonSm,
                    child: Row(
                      children: <Widget>[
                        if (language.isEmpty)
                          const Spacer()
                        else
                          Expanded(
                            child: Text(
                              language,
                              maxLines: 1,
                              overflow: .ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: AleraTokens.foregroundMuted,
                                  ),
                            ),
                          ),
                        if (widget.showCopy)
                          _AleraCodeCopyButton(
                            code: widget.code,
                            hovered: _hovered,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(
                height: AleraTokens.dividerExtent,
                thickness: AleraTokens.dividerExtent,
                color: AleraTokens.borderSubtle,
              ),
            ],
            // A plain horizontal scroll: code sits inside vertical lists, and
            // claiming the mouse wheel here would stall scrolling the list.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(AleraTokens.space12),
              child: Text.rich(
                widget.highlighted ?? TextSpan(text: widget.code),
                style: AleraTokens.monoStyle.copyWith(
                  color: AleraTokens.foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Copy button that stays in the tree for keyboard and semantics, and only
/// shows while the block is hovered, the button is focused, or the check mark
/// confirms a copy.
class const _AleraCodeCopyButton({
  required final String code,
  required final ValueListenable<bool> hovered,
}) extends StatefulWidget {
  @override
  State<_AleraCodeCopyButton> createState() => _AleraCodeCopyButtonState();
}

class _AleraCodeCopyButtonState extends State<_AleraCodeCopyButton> {
  Timer? _resetCopied;
  bool _copied = false;
  bool _focused = false;

  @override
  void dispose() {
    _resetCopied?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.code));
    } on PlatformException {
      // Nothing reached the clipboard, so the button must not claim it did.
      return;
    }
    if (!mounted) {
      return;
    }
    _resetCopied?.cancel();
    _resetCopied = Timer(_copiedFeedbackDuration, () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
    setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final button = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: AleraIconButton(
        tooltip: _copied ? 'Copied' : 'Copy Code',
        icon: _copied ? AleraIcons.check : AleraIcons.copy,
        iconSize: AleraTokens.iconMd,
        minSize: AleraTokens.iconButtonSm,
        onPressed: () => unawaited(_copy()),
      ),
    );
    return ValueListenableBuilder<bool>(
      valueListenable: widget.hovered,
      child: button,
      builder: (context, hovered, child) => AnimatedOpacity(
        opacity: hovered || _focused || _copied ? 1 : 0,
        duration: AleraTokens.durationFast,
        alwaysIncludeSemantics: true,
        child: child,
      ),
    );
  }
}
