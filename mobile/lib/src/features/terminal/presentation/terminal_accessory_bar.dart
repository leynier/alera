import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_accessory_key.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_input_mode.dart';
import 'package:flutter/material.dart';

/// Quick-key strip shown above the keyboard in both input modes.
///
/// Paste and the visible vertical navigation keys stay pinned while the
/// remaining user-configured keys scroll. Repeatable keys auto-repeat while
/// long-pressed. Presentational: actions flow out via callbacks and
/// configuration lives with the caller.
class TerminalAccessoryBar extends StatelessWidget {
  const TerminalAccessoryBar({
    super.key,
    required this.keys,
    required this.inputMode,
    required this.onKey,
    required this.onPaste,
    required this.onToggleMode,
  });

  final List<TerminalAccessoryKey> keys;
  final TerminalInputMode inputMode;
  final ValueChanged<List<int>> onKey;
  final Future<void> Function() onPaste;
  final VoidCallback onToggleMode;

  @override
  Widget build(BuildContext context) {
    final pinnedKeys = <TerminalAccessoryKey>[
      for (final id in pinnedTerminalAccessoryKeyIds)
        for (final key in keys)
          if (key.id == id) key,
    ];
    final scrollingKeys = <TerminalAccessoryKey>[
      for (final key in keys)
        if (!pinnedTerminalAccessoryKeyIds.contains(key.id)) key,
    ];
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
                itemCount: scrollingKeys.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AleraTokens.spaceXs),
                itemBuilder: (context, index) {
                  final key = scrollingKeys[index];
                  return _AccessoryKeyButton(accessoryKey: key, onKey: onKey);
                },
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: AleraTokens.surfaceElevated,
                border: Border(
                  left: BorderSide(color: AleraTokens.borderSubtle),
                ),
              ),
              padding: const EdgeInsets.symmetric(
                vertical: AleraTokens.spaceXs,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _PriorityActionButton(
                    tooltip: 'Paste Clipboard',
                    icon: AleraIcons.paste,
                    onPressed: onPaste,
                  ),
                  for (final key in pinnedKeys) ...<Widget>[
                    const SizedBox(width: AleraTokens.space2),
                    _AccessoryKeyButton(
                      accessoryKey: key,
                      onKey: onKey,
                      pinned: true,
                    ),
                  ],
                ],
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
  const _AccessoryKeyButton({
    required this.accessoryKey,
    required this.onKey,
    this.pinned = false,
  });

  final TerminalAccessoryKey accessoryKey;
  final ValueChanged<List<int>> onKey;
  final bool pinned;

  @override
  State<_AccessoryKeyButton> createState() => _AccessoryKeyButtonState();
}

class _AccessoryKeyButtonState extends State<_AccessoryKeyButton> {
  Timer? _repeatTimer;
  bool _pressed = false;

  @override
  void dispose() {
    _repeatTimer?.cancel();
    super.dispose();
  }

  void _startRepeat() {
    _setPressed(true);
    widget.onKey(widget.accessoryKey.bytes);
    _repeatTimer = Timer.periodic(AleraTokens.keyRepeatInterval, (_) {
      widget.onKey(widget.accessoryKey.bytes);
    });
  }

  void _stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _setPressed(false);
  }

  void _setPressed(bool value) {
    if (mounted && _pressed != value) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = AnimatedContainer(
      duration: AleraTokens.durationFast,
      width: widget.pinned ? AleraTokens.minTapTarget : null,
      constraints: const BoxConstraints(
        minWidth: AleraTokens.minTapTarget,
        minHeight: AleraTokens.minTapTarget,
      ),
      padding: widget.pinned
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: AleraTokens.spaceMd),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _pressed
            ? AleraTokens.accentSubtle
            : widget.pinned
            ? AleraTokens.surfaceVariant
            : AleraTokens.surfaceElevated,
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
      key: ValueKey<String>('terminal-accessory-${widget.accessoryKey.id}'),
      button: true,
      label: widget.accessoryKey.accessibilityLabel,
      child: widget.accessoryKey.repeatable
          ? GestureDetector(
              onTap: () => widget.onKey(widget.accessoryKey.bytes),
              onTapDown: (_) => _setPressed(true),
              onTapUp: (_) => _setPressed(false),
              onTapCancel: () => _setPressed(false),
              onLongPressStart: (_) => _startRepeat(),
              onLongPressEnd: (_) => _stopRepeat(),
              onLongPressCancel: _stopRepeat,
              child: child,
            )
          : Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
                onTap: () => widget.onKey(widget.accessoryKey.bytes),
                child: child,
              ),
            ),
    );
  }
}

class _PriorityActionButton extends StatelessWidget {
  const _PriorityActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: AleraTokens.minTapTarget,
      child: IconButton(
        tooltip: tooltip,
        onPressed: () => unawaited(onPressed()),
        style: IconButton.styleFrom(
          backgroundColor: AleraTokens.accentSubtle,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
            side: const BorderSide(color: AleraTokens.borderSubtle),
          ),
        ),
        icon: Icon(icon),
      ),
    );
  }
}
