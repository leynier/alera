import 'package:flutter/services.dart';

/// Result of validating/parsing a keyboard chord string.
sealed class KeyChordParseResult {
  const KeyChordParseResult();
}

final class KeyChordParseSuccess extends KeyChordParseResult {
  const KeyChordParseSuccess(this.chord);

  final KeyChord chord;
}

final class KeyChordParseFailure extends KeyChordParseResult {
  const KeyChordParseFailure(this.message);

  final String message;
}

/// Snapshot of the modifier keys held down when a key event fires. Kept as a
/// plain value so chord matching stays pure and unit-testable without a live
/// [HardwareKeyboard].
class KeyModifierState {
  const KeyModifierState({
    this.meta = false,
    this.control = false,
    this.alt = false,
    this.shift = false,
  });

  factory KeyModifierState.fromKeyboard(HardwareKeyboard keyboard) {
    return KeyModifierState(
      meta: keyboard.isMetaPressed,
      control: keyboard.isControlPressed,
      alt: keyboard.isAltPressed,
      shift: keyboard.isShiftPressed,
    );
  }

  final bool meta;
  final bool control;
  final bool alt;
  final bool shift;
}

/// An immutable keyboard chord: a set of modifiers plus a single trigger key.
///
/// The `Mod` modifier is platform-neutral and resolves to Command on macOS and
/// Control elsewhere. It is resolved at match/format time, never stored as a
/// concrete modifier, so the same chord serializes identically across platforms.
class KeyChord {
  const KeyChord({
    required this.trigger,
    this.useMod = false,
    this.meta = false,
    this.control = false,
    this.alt = false,
    this.shift = false,
  });

  /// Whether the platform-neutral `Mod` modifier is required.
  final bool useMod;

  /// Whether the Command/Meta (⌘) modifier is explicitly required.
  final bool meta;

  /// Whether the Control modifier is explicitly required.
  final bool control;

  /// Whether the Alt/Option modifier is required.
  final bool alt;

  /// Whether the Shift modifier is required.
  final bool shift;

  /// The non-modifier key that triggers the chord.
  final LogicalKeyboardKey trigger;

  bool get hasModifier => useMod || meta || control || alt;

  /// Resolved meta requirement for [isMacOS].
  bool _metaRequired({required bool isMacOS}) => meta || (useMod && isMacOS);

  /// Resolved control requirement for [isMacOS].
  bool _controlRequired({required bool isMacOS}) =>
      control || (useMod && !isMacOS);

  /// Parses a chord string such as `Mod+Shift+P`, `Ctrl+T` or `Mod+,`.
  ///
  /// Modifier tokens are case-insensitive. Symbol triggers (`,`, `[`, `]`, …)
  /// are accepted and normalized to their canonical token names.
  static KeyChordParseResult parse(String value) {
    final rawParts = value
        .split('+')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (rawParts.isEmpty) {
      return const KeyChordParseFailure('Enter a shortcut like Ctrl+Shift+P.');
    }

    var useMod = false;
    var meta = false;
    var control = false;
    var alt = false;
    var shift = false;
    LogicalKeyboardKey? trigger;

    for (final part in rawParts) {
      final lower = part.toLowerCase();
      switch (lower) {
        case 'mod':
        case 'cmdorctrl':
          useMod = true;
        case 'cmd':
        case 'command':
        case 'meta':
        case 'super':
        case 'win':
          meta = true;
        case 'ctrl':
        case 'control':
          control = true;
        case 'alt':
        case 'option':
        case 'opt':
          alt = true;
        case 'shift':
          shift = true;
        default:
          if (trigger != null) {
            return const KeyChordParseFailure(
              'A shortcut can only have one main key.',
            );
          }
          final key = _triggerFromToken(part);
          if (key == null) {
            return KeyChordParseFailure('Unsupported key: $part.');
          }
          trigger = key;
      }
    }

    if (trigger == null) {
      return const KeyChordParseFailure('Add a main key, like P or Enter.');
    }
    if (useMod && (meta || control)) {
      return const KeyChordParseFailure(
        'Use either Mod or a platform-specific modifier, not both.',
      );
    }

    final chord = KeyChord(
      trigger: trigger,
      useMod: useMod,
      meta: meta,
      control: control,
      alt: alt,
      shift: shift,
    );
    if (!chord.hasModifier && !_isSafeBareTrigger(trigger)) {
      return const KeyChordParseFailure('Include at least one modifier key.');
    }
    return KeyChordParseSuccess(chord);
  }

  /// Builds a chord from a captured [KeyDownEvent] and the held [modifiers].
  /// Returns a failure when the event is a lone modifier press or the trigger
  /// key is unsupported.
  static KeyChordParseResult fromKeyEvent(
    KeyEvent event,
    KeyModifierState modifiers, {
    required bool isMacOS,
  }) {
    final logical = event.logicalKey;
    if (_isModifierKey(logical)) {
      return const KeyChordParseFailure('Press a non-modifier key too.');
    }
    final token = _keyToToken[logical];
    if (token == null) {
      return const KeyChordParseFailure('Unsupported key.');
    }
    // Collapse the platform modifier into `Mod` so the captured chord
    // serializes the same way the defaults do.
    final isMod = isMacOS ? modifiers.meta : modifiers.control;
    final chord = KeyChord(
      trigger: logical,
      useMod: isMod,
      meta: isMacOS ? false : modifiers.meta,
      control: isMacOS ? modifiers.control : false,
      alt: modifiers.alt,
      shift: modifiers.shift,
    );
    if (!chord.hasModifier && !_isSafeBareTrigger(logical)) {
      return const KeyChordParseFailure('Include at least one modifier key.');
    }
    return KeyChordParseSuccess(chord);
  }

  /// Whether this chord matches the given [event] under the held [modifiers].
  /// Only key-down events match.
  bool matches(
    KeyEvent event,
    KeyModifierState modifiers, {
    required bool isMacOS,
  }) {
    if (event is! KeyDownEvent) {
      return false;
    }
    if (event.logicalKey != trigger) {
      return false;
    }
    return modifiers.meta == _metaRequired(isMacOS: isMacOS) &&
        modifiers.control == _controlRequired(isMacOS: isMacOS) &&
        modifiers.alt == alt &&
        modifiers.shift == shift;
  }

  /// Canonical, platform-neutral serialization (`Mod+Shift+BracketRight`).
  String toCanonicalString() {
    final parts = <String>[
      if (useMod) 'Mod',
      if (meta) 'Cmd',
      if (control) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
      _keyToToken[trigger] ?? trigger.keyLabel,
    ];
    return parts.join('+');
  }

  /// Human-readable label for the current platform. macOS uses symbol glyphs
  /// without separators (`⌘⇧P`); other platforms use `Ctrl+Shift+P`.
  String format({required bool isMacOS}) {
    final triggerLabel = _triggerDisplayLabel(trigger, isMacOS: isMacOS);
    if (isMacOS) {
      final buffer = StringBuffer()
        ..write(control ? '⌃' : '')
        ..write(alt ? '⌥' : '')
        ..write(shift ? '⇧' : '')
        ..write((meta || useMod) ? '⌘' : '')
        ..write(triggerLabel);
      return buffer.toString();
    }
    final parts = <String>[
      if (control || useMod) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
      if (meta) 'Meta',
      triggerLabel,
    ];
    return parts.join('+');
  }

  @override
  bool operator ==(Object other) {
    return other is KeyChord &&
        other.useMod == useMod &&
        other.meta == meta &&
        other.control == control &&
        other.alt == alt &&
        other.shift == shift &&
        other.trigger == trigger;
  }

  @override
  int get hashCode => Object.hash(useMod, meta, control, alt, shift, trigger);

  @override
  String toString() => 'KeyChord(${toCanonicalString()})';
}

bool _isModifierKey(LogicalKeyboardKey key) {
  return key == LogicalKeyboardKey.shift ||
      key == LogicalKeyboardKey.shiftLeft ||
      key == LogicalKeyboardKey.shiftRight ||
      key == LogicalKeyboardKey.control ||
      key == LogicalKeyboardKey.controlLeft ||
      key == LogicalKeyboardKey.controlRight ||
      key == LogicalKeyboardKey.alt ||
      key == LogicalKeyboardKey.altLeft ||
      key == LogicalKeyboardKey.altRight ||
      key == LogicalKeyboardKey.meta ||
      key == LogicalKeyboardKey.metaLeft ||
      key == LogicalKeyboardKey.metaRight;
}

/// Function keys and a few navigation keys are allowed without a modifier.
bool _isSafeBareTrigger(LogicalKeyboardKey key) {
  return _functionKeys.contains(key);
}

LogicalKeyboardKey? _triggerFromToken(String token) {
  final symbol = _symbolAliases[token];
  if (symbol != null) {
    return symbol;
  }
  return _tokenToKey[token.toLowerCase()];
}

String _triggerDisplayLabel(LogicalKeyboardKey key, {required bool isMacOS}) {
  final display = _displayLabels[key];
  if (display != null) {
    return display;
  }
  final token = _keyToToken[key];
  if (token != null && token.length == 1) {
    return token;
  }
  return token ?? key.keyLabel;
}

// --- Token tables -----------------------------------------------------------

final Map<String, LogicalKeyboardKey> _symbolAliases =
    <String, LogicalKeyboardKey>{
      ',': LogicalKeyboardKey.comma,
      '.': LogicalKeyboardKey.period,
      '/': LogicalKeyboardKey.slash,
      '\\': LogicalKeyboardKey.backslash,
      '[': LogicalKeyboardKey.bracketLeft,
      ']': LogicalKeyboardKey.bracketRight,
      '-': LogicalKeyboardKey.minus,
      '=': LogicalKeyboardKey.equal,
      ';': LogicalKeyboardKey.semicolon,
      "'": LogicalKeyboardKey.quote,
      '`': LogicalKeyboardKey.backquote,
    };

final Set<LogicalKeyboardKey> _functionKeys = <LogicalKeyboardKey>{
  LogicalKeyboardKey.f1,
  LogicalKeyboardKey.f2,
  LogicalKeyboardKey.f3,
  LogicalKeyboardKey.f4,
  LogicalKeyboardKey.f5,
  LogicalKeyboardKey.f6,
  LogicalKeyboardKey.f7,
  LogicalKeyboardKey.f8,
  LogicalKeyboardKey.f9,
  LogicalKeyboardKey.f10,
  LogicalKeyboardKey.f11,
  LogicalKeyboardKey.f12,
};

/// Lowercased token -> logical key, for parsing canonical strings.
final Map<String, LogicalKeyboardKey> _tokenToKey =
    <String, LogicalKeyboardKey>{
      for (final entry in _keyToToken.entries)
        entry.value.toLowerCase(): entry.key,
    };

/// Logical key -> canonical token. Drives serialization and reverse lookup.
final Map<LogicalKeyboardKey, String> _keyToToken =
    <LogicalKeyboardKey, String>{
      // Letters.
      LogicalKeyboardKey.keyA: 'A',
      LogicalKeyboardKey.keyB: 'B',
      LogicalKeyboardKey.keyC: 'C',
      LogicalKeyboardKey.keyD: 'D',
      LogicalKeyboardKey.keyE: 'E',
      LogicalKeyboardKey.keyF: 'F',
      LogicalKeyboardKey.keyG: 'G',
      LogicalKeyboardKey.keyH: 'H',
      LogicalKeyboardKey.keyI: 'I',
      LogicalKeyboardKey.keyJ: 'J',
      LogicalKeyboardKey.keyK: 'K',
      LogicalKeyboardKey.keyL: 'L',
      LogicalKeyboardKey.keyM: 'M',
      LogicalKeyboardKey.keyN: 'N',
      LogicalKeyboardKey.keyO: 'O',
      LogicalKeyboardKey.keyP: 'P',
      LogicalKeyboardKey.keyQ: 'Q',
      LogicalKeyboardKey.keyR: 'R',
      LogicalKeyboardKey.keyS: 'S',
      LogicalKeyboardKey.keyT: 'T',
      LogicalKeyboardKey.keyU: 'U',
      LogicalKeyboardKey.keyV: 'V',
      LogicalKeyboardKey.keyW: 'W',
      LogicalKeyboardKey.keyX: 'X',
      LogicalKeyboardKey.keyY: 'Y',
      LogicalKeyboardKey.keyZ: 'Z',
      // Digits.
      LogicalKeyboardKey.digit0: '0',
      LogicalKeyboardKey.digit1: '1',
      LogicalKeyboardKey.digit2: '2',
      LogicalKeyboardKey.digit3: '3',
      LogicalKeyboardKey.digit4: '4',
      LogicalKeyboardKey.digit5: '5',
      LogicalKeyboardKey.digit6: '6',
      LogicalKeyboardKey.digit7: '7',
      LogicalKeyboardKey.digit8: '8',
      LogicalKeyboardKey.digit9: '9',
      // Punctuation.
      LogicalKeyboardKey.comma: 'Comma',
      LogicalKeyboardKey.period: 'Period',
      LogicalKeyboardKey.slash: 'Slash',
      LogicalKeyboardKey.backslash: 'Backslash',
      LogicalKeyboardKey.bracketLeft: 'BracketLeft',
      LogicalKeyboardKey.bracketRight: 'BracketRight',
      LogicalKeyboardKey.minus: 'Minus',
      LogicalKeyboardKey.equal: 'Equal',
      LogicalKeyboardKey.semicolon: 'Semicolon',
      LogicalKeyboardKey.quote: 'Quote',
      LogicalKeyboardKey.backquote: 'Backquote',
      // Navigation and editing.
      LogicalKeyboardKey.tab: 'Tab',
      LogicalKeyboardKey.enter: 'Enter',
      LogicalKeyboardKey.escape: 'Escape',
      LogicalKeyboardKey.space: 'Space',
      LogicalKeyboardKey.backspace: 'Backspace',
      LogicalKeyboardKey.delete: 'Delete',
      LogicalKeyboardKey.insert: 'Insert',
      LogicalKeyboardKey.home: 'Home',
      LogicalKeyboardKey.end: 'End',
      LogicalKeyboardKey.pageUp: 'PageUp',
      LogicalKeyboardKey.pageDown: 'PageDown',
      LogicalKeyboardKey.arrowUp: 'ArrowUp',
      LogicalKeyboardKey.arrowDown: 'ArrowDown',
      LogicalKeyboardKey.arrowLeft: 'ArrowLeft',
      LogicalKeyboardKey.arrowRight: 'ArrowRight',
      // Function keys.
      LogicalKeyboardKey.f1: 'F1',
      LogicalKeyboardKey.f2: 'F2',
      LogicalKeyboardKey.f3: 'F3',
      LogicalKeyboardKey.f4: 'F4',
      LogicalKeyboardKey.f5: 'F5',
      LogicalKeyboardKey.f6: 'F6',
      LogicalKeyboardKey.f7: 'F7',
      LogicalKeyboardKey.f8: 'F8',
      LogicalKeyboardKey.f9: 'F9',
      LogicalKeyboardKey.f10: 'F10',
      LogicalKeyboardKey.f11: 'F11',
      LogicalKeyboardKey.f12: 'F12',
    };

/// Logical key -> display glyph for chord labels.
final Map<LogicalKeyboardKey, String> _displayLabels =
    <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.comma: ',',
      LogicalKeyboardKey.period: '.',
      LogicalKeyboardKey.slash: '/',
      LogicalKeyboardKey.backslash: r'\',
      LogicalKeyboardKey.bracketLeft: '[',
      LogicalKeyboardKey.bracketRight: ']',
      LogicalKeyboardKey.minus: '-',
      LogicalKeyboardKey.equal: '=',
      LogicalKeyboardKey.semicolon: ';',
      LogicalKeyboardKey.quote: "'",
      LogicalKeyboardKey.backquote: '`',
      LogicalKeyboardKey.tab: 'Tab',
      LogicalKeyboardKey.enter: 'Enter',
      LogicalKeyboardKey.escape: 'Esc',
      LogicalKeyboardKey.space: 'Space',
      LogicalKeyboardKey.backspace: 'Backspace',
      LogicalKeyboardKey.delete: 'Delete',
      LogicalKeyboardKey.insert: 'Insert',
      LogicalKeyboardKey.home: 'Home',
      LogicalKeyboardKey.end: 'End',
      LogicalKeyboardKey.pageUp: 'PageUp',
      LogicalKeyboardKey.pageDown: 'PageDown',
      LogicalKeyboardKey.arrowUp: '↑',
      LogicalKeyboardKey.arrowDown: '↓',
      LogicalKeyboardKey.arrowLeft: '←',
      LogicalKeyboardKey.arrowRight: '→',
    };
