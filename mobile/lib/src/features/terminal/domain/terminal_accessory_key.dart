import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:flutter/widgets.dart';

/// Something the accessory bar can invoke that is not a byte sequence.
enum TerminalAccessoryAction { paste }

/// One quick key on the terminal accessory bar. Ported from Orca's
/// terminal-accessory-keys registry (reference_projects/orca/mobile/src/terminal/).
///
/// The type is sealed so the bar's tap handler switches exhaustively: a key
/// either writes bytes straight to the PTY or runs an action that needs its own
/// delivery path. A single class with a nullable action would leave `bytes`
/// meaningless for action keys, and the failure mode of getting that convention
/// wrong is writing garbage into a live terminal.
sealed class TerminalAccessoryKey {
  const TerminalAccessoryKey({
    required this.id,
    required this.label,
    required this.accessibilityLabel,
  });

  final String id;
  final String label;
  final String accessibilityLabel;
}

/// A key whose [bytes] are the exact sequence written to the PTY.
final class TerminalAccessoryBytesKey extends TerminalAccessoryKey {
  const TerminalAccessoryBytesKey({
    required super.id,
    required super.label,
    required super.accessibilityLabel,
    required this.bytes,
    this.repeatable = false,
  });

  final List<int> bytes;

  /// Long-press auto-repeat, for arrows and deletion keys.
  final bool repeatable;
}

/// A key that runs an action instead of writing bytes, so it can take an async
/// path such as reading the clipboard and delivering it with bracketed paste.
final class TerminalAccessoryActionKey extends TerminalAccessoryKey {
  const TerminalAccessoryActionKey({
    required super.id,
    required super.label,
    required super.accessibilityLabel,
    required this.action,
    required this.icon,
  });

  final TerminalAccessoryAction action;

  /// Action keys render a glyph; there is no literal key cap to spell.
  final IconData icon;
}

const int _esc = 0x1b;

/// Canonical built-in ordering. New built-ins added here merge into saved
/// layouts next to their canonical neighbors.
///
/// The vertical arrows lead because they are the most used keys and this strip
/// scrolls: whatever sits first is what a user finds without swiping.
const List<TerminalAccessoryKey> builtInTerminalAccessoryKeys =
    <TerminalAccessoryKey>[
      TerminalAccessoryBytesKey(
        id: 'arrowUp',
        label: '↑',
        bytes: <int>[_esc, 0x5b, 0x41],
        accessibilityLabel: 'Arrow Up',
        repeatable: true,
      ),
      TerminalAccessoryBytesKey(
        id: 'arrowDown',
        label: '↓',
        bytes: <int>[_esc, 0x5b, 0x42],
        accessibilityLabel: 'Arrow Down',
        repeatable: true,
      ),
      // Merges into an existing saved layout right after arrowDown, which is
      // where the old fixed rail put it.
      TerminalAccessoryActionKey(
        id: 'paste',
        label: 'Paste',
        accessibilityLabel: 'Paste Clipboard',
        action: TerminalAccessoryAction.paste,
        icon: AleraIcons.paste,
      ),
      TerminalAccessoryBytesKey(
        id: 'escape',
        label: 'Esc',
        bytes: <int>[_esc],
        accessibilityLabel: 'Escape',
      ),
      TerminalAccessoryBytesKey(
        id: 'tab',
        label: 'Tab',
        bytes: <int>[0x09],
        accessibilityLabel: 'Tab',
      ),
      TerminalAccessoryBytesKey(
        id: 'enter',
        label: 'Enter',
        bytes: <int>[0x0d],
        accessibilityLabel: 'Enter',
      ),
      // Terminal apps recognize ESC [ Z as the reverse-tab sequence.
      TerminalAccessoryBytesKey(
        id: 'shiftTab',
        label: 'Shift+Tab',
        bytes: <int>[_esc, 0x5b, 0x5a],
        accessibilityLabel: 'Shift Tab',
      ),
      TerminalAccessoryBytesKey(
        id: 'space',
        label: 'Space',
        bytes: <int>[0x20],
        accessibilityLabel: 'Space',
      ),
      TerminalAccessoryBytesKey(
        id: 'backspace',
        label: '⌫',
        bytes: <int>[0x7f],
        accessibilityLabel: 'Backspace',
        repeatable: true,
      ),
      TerminalAccessoryBytesKey(
        id: 'delete',
        label: 'Del',
        bytes: <int>[_esc, 0x5b, 0x33, 0x7e],
        accessibilityLabel: 'Forward Delete',
        repeatable: true,
      ),
      TerminalAccessoryBytesKey(
        id: 'arrowLeft',
        label: '←',
        bytes: <int>[_esc, 0x5b, 0x44],
        accessibilityLabel: 'Arrow Left',
        repeatable: true,
      ),
      TerminalAccessoryBytesKey(
        id: 'arrowRight',
        label: '→',
        bytes: <int>[_esc, 0x5b, 0x43],
        accessibilityLabel: 'Arrow Right',
        repeatable: true,
      ),
      TerminalAccessoryBytesKey(
        id: 'ctrlC',
        label: 'Ctrl+C',
        bytes: <int>[0x03],
        accessibilityLabel: 'Interrupt Terminal',
      ),
      TerminalAccessoryBytesKey(
        id: 'ctrlD',
        label: 'Ctrl+D',
        bytes: <int>[0x04],
        accessibilityLabel: 'Send EOF',
      ),
      TerminalAccessoryBytesKey(
        id: 'ctrlL',
        label: 'Ctrl+L',
        bytes: <int>[0x0c],
        accessibilityLabel: 'Clear Screen',
      ),
      TerminalAccessoryBytesKey(
        id: 'ctrlZ',
        label: 'Ctrl+Z',
        bytes: <int>[0x1a],
        accessibilityLabel: 'Suspend Process',
      ),
      TerminalAccessoryBytesKey(
        id: 'ctrlR',
        label: 'Ctrl+R',
        bytes: <int>[0x12],
        accessibilityLabel: 'Reverse Search',
      ),
      TerminalAccessoryBytesKey(
        id: 'ctrlA',
        label: 'Ctrl+A',
        bytes: <int>[0x01],
        accessibilityLabel: 'Start Of Line',
      ),
      TerminalAccessoryBytesKey(
        id: 'ctrlE',
        label: 'Ctrl+E',
        bytes: <int>[0x05],
        accessibilityLabel: 'End Of Line',
      ),
      TerminalAccessoryBytesKey(
        id: 'ctrlW',
        label: 'Ctrl+W',
        bytes: <int>[0x17],
        accessibilityLabel: 'Delete Word Backward',
      ),
      TerminalAccessoryBytesKey(
        id: 'ctrlU',
        label: 'Ctrl+U',
        bytes: <int>[0x15],
        accessibilityLabel: 'Clear Line Before Cursor',
      ),
    ];

final Map<String, TerminalAccessoryKey> builtInTerminalAccessoryKeysById =
    <String, TerminalAccessoryKey>{
      for (final key in builtInTerminalAccessoryKeys) key.id: key,
    };
