/// One quick key on the terminal accessory bar. [bytes] is the exact byte
/// sequence written to the PTY. Ported from Orca's terminal-accessory-keys
/// registry (reference_projects/orca/mobile/src/terminal/).
class TerminalAccessoryKey {
  const TerminalAccessoryKey({
    required this.id,
    required this.label,
    required this.bytes,
    required this.accessibilityLabel,
    this.repeatable = false,
  });

  final String id;
  final String label;
  final List<int> bytes;
  final String accessibilityLabel;

  /// Long-press auto-repeat, for arrows and deletion keys.
  final bool repeatable;
}

const int _esc = 0x1b;

/// Canonical built-in ordering. New built-ins added here merge into saved
/// layouts next to their canonical neighbors.
const List<TerminalAccessoryKey> builtInTerminalAccessoryKeys =
    <TerminalAccessoryKey>[
      TerminalAccessoryKey(
        id: 'escape',
        label: 'Esc',
        bytes: <int>[_esc],
        accessibilityLabel: 'Escape',
      ),
      TerminalAccessoryKey(
        id: 'tab',
        label: 'Tab',
        bytes: <int>[0x09],
        accessibilityLabel: 'Tab',
      ),
      TerminalAccessoryKey(
        id: 'enter',
        label: 'Enter',
        bytes: <int>[0x0d],
        accessibilityLabel: 'Enter',
      ),
      // Terminal apps recognize ESC [ Z as the reverse-tab sequence.
      TerminalAccessoryKey(
        id: 'shiftTab',
        label: 'Shift+Tab',
        bytes: <int>[_esc, 0x5b, 0x5a],
        accessibilityLabel: 'Shift Tab',
      ),
      TerminalAccessoryKey(
        id: 'space',
        label: 'Space',
        bytes: <int>[0x20],
        accessibilityLabel: 'Space',
      ),
      TerminalAccessoryKey(
        id: 'backspace',
        label: '⌫',
        bytes: <int>[0x7f],
        accessibilityLabel: 'Backspace',
        repeatable: true,
      ),
      TerminalAccessoryKey(
        id: 'delete',
        label: 'Del',
        bytes: <int>[_esc, 0x5b, 0x33, 0x7e],
        accessibilityLabel: 'Forward Delete',
        repeatable: true,
      ),
      TerminalAccessoryKey(
        id: 'arrowUp',
        label: '↑',
        bytes: <int>[_esc, 0x5b, 0x41],
        accessibilityLabel: 'Arrow Up',
        repeatable: true,
      ),
      TerminalAccessoryKey(
        id: 'arrowDown',
        label: '↓',
        bytes: <int>[_esc, 0x5b, 0x42],
        accessibilityLabel: 'Arrow Down',
        repeatable: true,
      ),
      TerminalAccessoryKey(
        id: 'arrowLeft',
        label: '←',
        bytes: <int>[_esc, 0x5b, 0x44],
        accessibilityLabel: 'Arrow Left',
        repeatable: true,
      ),
      TerminalAccessoryKey(
        id: 'arrowRight',
        label: '→',
        bytes: <int>[_esc, 0x5b, 0x43],
        accessibilityLabel: 'Arrow Right',
        repeatable: true,
      ),
      TerminalAccessoryKey(
        id: 'ctrlC',
        label: 'Ctrl+C',
        bytes: <int>[0x03],
        accessibilityLabel: 'Interrupt Terminal',
      ),
      TerminalAccessoryKey(
        id: 'ctrlD',
        label: 'Ctrl+D',
        bytes: <int>[0x04],
        accessibilityLabel: 'Send EOF',
      ),
      TerminalAccessoryKey(
        id: 'ctrlL',
        label: 'Ctrl+L',
        bytes: <int>[0x0c],
        accessibilityLabel: 'Clear Screen',
      ),
      TerminalAccessoryKey(
        id: 'ctrlZ',
        label: 'Ctrl+Z',
        bytes: <int>[0x1a],
        accessibilityLabel: 'Suspend Process',
      ),
      TerminalAccessoryKey(
        id: 'ctrlR',
        label: 'Ctrl+R',
        bytes: <int>[0x12],
        accessibilityLabel: 'Reverse Search',
      ),
      TerminalAccessoryKey(
        id: 'ctrlA',
        label: 'Ctrl+A',
        bytes: <int>[0x01],
        accessibilityLabel: 'Start Of Line',
      ),
      TerminalAccessoryKey(
        id: 'ctrlE',
        label: 'Ctrl+E',
        bytes: <int>[0x05],
        accessibilityLabel: 'End Of Line',
      ),
      TerminalAccessoryKey(
        id: 'ctrlW',
        label: 'Ctrl+W',
        bytes: <int>[0x17],
        accessibilityLabel: 'Delete Word Backward',
      ),
      TerminalAccessoryKey(
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
