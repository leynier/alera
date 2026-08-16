import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_accessory_key.dart';
import 'package:flutter/material.dart';

/// Quick-key strip shown above the keyboard in both input modes.
///
/// Every key is equal: order and visibility come from the saved layout and
/// nothing is pinned, so the strip gets the full width instead of sharing it
/// with a fixed rail. Repeatable keys auto-repeat while long-pressed.
/// Presentational: actions flow out via callbacks and configuration lives with
/// the caller.
class TerminalAccessoryBar extends StatelessWidget {
  const TerminalAccessoryBar({
    super.key,
    required this.keys,
    required this.onKey,
    required this.onAction,
  });

  final List<TerminalAccessoryKey> keys;
  final ValueChanged<List<int>> onKey;
  final Future<void> Function(TerminalAccessoryAction action) onAction;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AleraTokens.surface,
      child: SizedBox(
        height: AleraTokens.accessoryBarHeight,
        child: _AccessoryKeyStrip(keys: keys, onKey: onKey, onAction: onAction),
      ),
    );
  }
}

/// The scrolling row of keys, with a fade at whichever edge has more keys
/// behind it. Without the fade a key cut off by the viewport reads as a
/// squashed button rather than as a row that continues.
class _AccessoryKeyStrip extends StatefulWidget {
  const _AccessoryKeyStrip({
    required this.keys,
    required this.onKey,
    required this.onAction,
  });

  final List<TerminalAccessoryKey> keys;
  final ValueChanged<List<int>> onKey;
  final Future<void> Function(TerminalAccessoryAction action) onAction;

  @override
  State<_AccessoryKeyStrip> createState() => _AccessoryKeyStripState();
}

class _AccessoryKeyStripState extends State<_AccessoryKeyStrip> {
  final ScrollController _controller = ScrollController();
  bool _fadeStart = false;
  bool _fadeEnd = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncFades);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFades());
  }

  @override
  void didUpdateWidget(_AccessoryKeyStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keys.length != widget.keys.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncFades());
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncFades() {
    if (!mounted || !_controller.hasClients) {
      return;
    }
    final position = _controller.position;
    final start = position.extentBefore > 0;
    final end = position.extentAfter > 0;
    if (start != _fadeStart || end != _fadeEnd) {
      setState(() {
        _fadeStart = start;
        _fadeEnd = end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        ListView.separated(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.terminalInputInset,
            vertical: AleraTokens.spaceXs,
          ),
          itemCount: widget.keys.length,
          separatorBuilder: (_, _) =>
              const SizedBox(width: AleraTokens.terminalInputInset),
          itemBuilder: (context, index) => _AccessoryKeyButton(
            accessoryKey: widget.keys[index],
            onKey: widget.onKey,
            onAction: widget.onAction,
          ),
        ),
        if (_fadeStart)
          const _EdgeFade(
            alignment: Alignment.centerLeft,
            valueKey: ValueKey<String>('terminal-accessory-fade-start'),
          ),
        if (_fadeEnd)
          const _EdgeFade(
            alignment: Alignment.centerRight,
            valueKey: ValueKey<String>('terminal-accessory-fade-end'),
          ),
      ],
    );
  }
}

class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.alignment, required this.valueKey});

  final Alignment alignment;
  final ValueKey<String> valueKey;

  @override
  Widget build(BuildContext context) {
    final toEdge = alignment == Alignment.centerLeft;
    return Positioned.fill(
      key: valueKey,
      child: IgnorePointer(
        child: Align(
          alignment: alignment,
          child: Container(
            width: AleraTokens.terminalAccessoryFadeWidth,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: toEdge ? Alignment.centerLeft : Alignment.centerRight,
                end: toEdge ? Alignment.centerRight : Alignment.centerLeft,
                colors: <Color>[
                  AleraTokens.surface,
                  AleraTokens.surface.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AccessoryKeyButton extends StatefulWidget {
  const _AccessoryKeyButton({
    required this.accessoryKey,
    required this.onKey,
    required this.onAction,
  });

  final TerminalAccessoryKey accessoryKey;
  final ValueChanged<List<int>> onKey;
  final Future<void> Function(TerminalAccessoryAction action) onAction;

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

  void _activate() {
    switch (widget.accessoryKey) {
      case TerminalAccessoryBytesKey(:final bytes):
        widget.onKey(bytes);
      case TerminalAccessoryActionKey(:final action):
        unawaited(widget.onAction(action));
    }
  }

  void _startRepeat() {
    _setPressed(true);
    _activate();
    _repeatTimer = Timer.periodic(AleraTokens.keyRepeatInterval, (_) {
      _activate();
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
    final key = widget.accessoryKey;
    final child = AnimatedContainer(
      duration: AleraTokens.durationFast,
      constraints: const BoxConstraints(
        minWidth: AleraTokens.minTapTarget,
        minHeight: AleraTokens.minTapTarget,
      ),
      padding: const EdgeInsets.symmetric(horizontal: AleraTokens.spaceMd),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _pressed
            ? AleraTokens.accentSubtle
            : AleraTokens.surfaceElevated,
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: switch (key) {
        TerminalAccessoryBytesKey() => Text(
          key.label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontFamily: AleraTokens.monoFontFamily,
          ),
        ),
        TerminalAccessoryActionKey(:final icon) => Icon(
          icon,
          size: AleraTokens.space20,
        ),
      },
    );
    final repeatable = key is TerminalAccessoryBytesKey && key.repeatable;
    return Semantics(
      key: ValueKey<String>('terminal-accessory-${key.id}'),
      button: true,
      label: key.accessibilityLabel,
      child: repeatable
          ? GestureDetector(
              onTap: _activate,
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
                onTap: _activate,
                child: child,
              ),
            ),
    );
  }
}
