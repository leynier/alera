import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_accessory_key.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_input_mode.dart';
import 'package:flutter/material.dart';

/// Quick-key strip shown above the keyboard in both input modes. Repeatable
/// keys auto-repeat while long-pressed. Presentational: bytes flow out via
/// [onKey], configuration lives with the caller.
class TerminalAccessoryBar extends StatelessWidget {
  const TerminalAccessoryBar({
    super.key,
    required this.keys,
    required this.inputMode,
    required this.onKey,
    required this.onToggleMode,
  });

  final List<TerminalAccessoryKey> keys;
  final TerminalInputMode inputMode;
  final ValueChanged<List<int>> onKey;
  final VoidCallback onToggleMode;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AleraTokens.surface,
      child: SizedBox(
        height: AleraTokens.accessoryBarHeight,
        child: Row(
          children: <Widget>[
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.spaceSm,
                  vertical: AleraTokens.spaceXs,
                ),
                itemCount: keys.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AleraTokens.spaceXs),
                itemBuilder: (context, index) {
                  final key = keys[index];
                  return _AccessoryKeyButton(accessoryKey: key, onKey: onKey);
                },
              ),
            ),
            IconButton(
              tooltip: inputMode == TerminalInputMode.compose
                  ? 'Switch To Direct Input'
                  : 'Switch To Compose Input',
              onPressed: onToggleMode,
              isSelected: inputMode == TerminalInputMode.direct,
              icon: const Icon(Icons.keyboard_alt_outlined),
              selectedIcon: const Icon(Icons.bolt),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessoryKeyButton extends StatefulWidget {
  const _AccessoryKeyButton({required this.accessoryKey, required this.onKey});

  final TerminalAccessoryKey accessoryKey;
  final ValueChanged<List<int>> onKey;

  @override
  State<_AccessoryKeyButton> createState() => _AccessoryKeyButtonState();
}

class _AccessoryKeyButtonState extends State<_AccessoryKeyButton> {
  Timer? _repeatTimer;

  @override
  void dispose() {
    _repeatTimer?.cancel();
    super.dispose();
  }

  void _startRepeat() {
    widget.onKey(widget.accessoryKey.bytes);
    _repeatTimer = Timer.periodic(AleraTokens.keyRepeatInterval, (_) {
      widget.onKey(widget.accessoryKey.bytes);
    });
  }

  void _stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: AleraTokens.spaceMd),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Text(
        widget.accessoryKey.label,
        style: theme.textTheme.labelLarge?.copyWith(
          fontFamily: AleraTokens.monoFontFamily,
        ),
      ),
    );
    return Semantics(
      button: true,
      label: widget.accessoryKey.accessibilityLabel,
      child: widget.accessoryKey.repeatable
          ? GestureDetector(
              onTap: () => widget.onKey(widget.accessoryKey.bytes),
              onLongPressStart: (_) => _startRepeat(),
              onLongPressEnd: (_) => _stopRepeat(),
              onLongPressCancel: _stopRepeat,
              child: child,
            )
          : InkWell(
              borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
              onTap: () => widget.onKey(widget.accessoryKey.bytes),
              child: child,
            ),
    );
  }
}
