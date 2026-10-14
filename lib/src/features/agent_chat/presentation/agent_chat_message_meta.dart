import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A message with its meta row (origin caption, time, Copy) underneath. The
/// row shows while the pointer is over the message or the keyboard focus is
/// inside it; while hidden it takes no pointer events and no focus, so it
/// neither catches stray clicks nor adds tab stops.
class const AgentChatMessageMeta({
  super.key,
  required final CrossAxisAlignment alignment,
  required final String copyText,
  required final DateTime? timestamp,
  required final WidgetBuilder builder,
  final String? caption,
}) extends StatefulWidget {
  @override
  State<AgentChatMessageMeta> createState() => _AgentChatMessageMetaState();
}

class _AgentChatMessageMetaState extends State<AgentChatMessageMeta> {
  final FocusNode _focus = FocusNode(debugLabel: 'Agent chat message');
  bool _hovered = false;
  bool _focused = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.copyText));
    AleraToast.publish(message: 'Copied to clipboard.');
  }

  @override
  Widget build(BuildContext context) {
    final timestamp = widget.timestamp;
    final localizations = MaterialLocalizations.of(context);
    final time = timestamp == null
        ? null
        : localizations.formatTimeOfDay(
            TimeOfDay.fromDateTime(timestamp.toLocal()),
          );
    final details = <String>[?widget.caption, ?time].join(' · ');
    final visible = _hovered || _focused;
    return Focus(
      focusNode: _focus,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Column(
          crossAxisAlignment: widget.alignment,
          children: <Widget>[
            widget.builder(context),
            ExcludeFocus(
              excluding: !visible,
              child: IgnorePointer(
                ignoring: !visible,
                child: AnimatedOpacity(
                  opacity: visible ? 1 : 0,
                  duration: AleraTokens.durationFast,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (details.isNotEmpty)
                        Text(details, style: AleraTokens.labelMicroFaintStyle),
                      AleraIconButton(
                        tooltip: 'Copy Message',
                        icon: AleraIcons.copy,
                        iconSize: AleraTokens.iconSm,
                        minSize: AleraTokens.iconButtonSm,
                        onPressed: widget.copyText.isEmpty
                            ? null
                            : () => unawaited(_copy()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
