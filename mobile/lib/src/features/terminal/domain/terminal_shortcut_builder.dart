/// Dart port of Orca's `buildTerminalShortcutKey` engine
/// (reference_projects/orca/mobile/src/terminal/terminal-accessory-keys.ts):
/// turns an arbitrary key-plus-modifiers binding into the escape bytes a
/// terminal expects, covering ctrl-letter arithmetic, alt as an ESC prefix,
/// shifted printables, CSI `1;N` modifier parameters for arrows and F-keys,
/// SS3 for unmodified F1-F4, and the Shift+Tab reverse-tab special case.
library;

enum TerminalShortcutModifier { ctrl, alt, shift }

class const TerminalShortcutBinding({
  required this.key,
  required final Set<TerminalShortcutModifier> modifiers,
}) {
  /// A special key id (see [terminalShortcutSpecialKeys]) or one printable
  /// ASCII character.
  final String key;
}

class const TerminalShortcutBuildResult({
  required final String label,
  required final List<int> bytes,
  required final String accessibilityLabel,
});

const int _esc = 0x1b;

const Map<String, String> _shiftedPrintable = <String, String>{
  '`': '~',
  '1': '!',
  '2': '@',
  '3': '#',
  '4': r'$',
  '5': '%',
  '6': '^',
  '7': '&',
  '8': '*',
  '9': '(',
  '0': ')',
  '-': '_',
  '=': '+',
  '[': '{',
  ']': '}',
  r'\': '|',
  ';': ':',
  "'": '"',
  ',': '<',
  '.': '>',
  '/': '?',
};

const Map<String, int> _ctrlPrintableBytes = <String, int>{
  ' ': 0x00,
  '@': 0x00,
  '`': 0x00,
  '[': 0x1b,
  '{': 0x1b,
  r'\': 0x1c,
  '|': 0x1c,
  ']': 0x1d,
  '}': 0x1d,
  '^': 0x1e,
  '~': 0x1e,
  '_': 0x1f,
  '?': 0x7f,
};

const Map<String, String> _specialKeyLabels = <String, String>{
  'escape': 'Esc',
  'tab': 'Tab',
  'enter': 'Enter',
  'backspace': '⌫',
  'delete': 'Del',
  'insert': 'Ins',
  'arrowUp': '↑',
  'arrowDown': '↓',
  'arrowLeft': '←',
  'arrowRight': '→',
  'home': 'Home',
  'end': 'End',
  'pageUp': 'PgUp',
  'pageDown': 'PgDn',
  'space': 'Space',
  'f1': 'F1',
  'f2': 'F2',
  'f3': 'F3',
  'f4': 'F4',
  'f5': 'F5',
  'f6': 'F6',
  'f7': 'F7',
  'f8': 'F8',
  'f9': 'F9',
  'f10': 'F10',
  'f11': 'F11',
  'f12': 'F12',
};

const Map<String, int> _csiFinalSpecialKeys = <String, int>{
  'arrowUp': 0x41,
  'arrowDown': 0x42,
  'arrowRight': 0x43,
  'arrowLeft': 0x44,
  'home': 0x48,
  'end': 0x46,
  'f1': 0x50,
  'f2': 0x51,
  'f3': 0x52,
  'f4': 0x53,
};

const Set<String> _ss3BaseSpecialKeys = <String>{'f1', 'f2', 'f3', 'f4'};

const Map<String, int> _csiTildeSpecialKeys = <String, int>{
  'insert': 2,
  'delete': 3,
  'pageUp': 5,
  'pageDown': 6,
  'f5': 15,
  'f6': 17,
  'f7': 18,
  'f8': 19,
  'f9': 20,
  'f10': 21,
  'f11': 23,
  'f12': 24,
};

/// Ids selectable in the custom-key picker, in display order.
final List<String> terminalShortcutSpecialKeys = List<String>.unmodifiableOf(
  _specialKeyLabels.keys,
);

String terminalShortcutSpecialKeyLabel(String id) =>
    _specialKeyLabels[id] ?? id;

TerminalShortcutBuildResult? buildTerminalShortcutKey(
  TerminalShortcutBinding binding,
) {
  final key = _normalizeShortcutKey(binding.key);
  if (key == null) {
    return null;
  }
  final modifiers = binding.modifiers;
  final bytes = _buildShortcutBytes(key, modifiers);
  if (bytes == null) {
    return null;
  }
  final label = _formatShortcutLabel(key, modifiers);
  return TerminalShortcutBuildResult(
    label: label,
    bytes: bytes,
    accessibilityLabel: label.replaceAll('+', ' '),
  );
}

List<int>? _buildShortcutBytes(
  String key,
  Set<TerminalShortcutModifier> modifiers,
) {
  if (key == 'space') {
    return _buildPrintableShortcutBytes(' ', modifiers);
  }
  final csiFinal = _csiFinalSpecialKeys[key];
  if (csiFinal != null) {
    // xterm encodes unmodified F1-F4 as SS3 (ESC O P/S). Once a modifier is
    // present it switches to the CSI 1;N form like arrows.
    if (_ss3BaseSpecialKeys.contains(key) &&
        _csiModifierParameter(modifiers) == 1) {
      return <int>[_esc, 0x4f, csiFinal];
    }
    return _buildCsiFinalShortcut(csiFinal, modifiers);
  }
  final csiTilde = _csiTildeSpecialKeys[key];
  if (csiTilde != null) {
    return _buildCsiTildeShortcut(csiTilde, modifiers);
  }
  final hasCtrl = modifiers.contains(TerminalShortcutModifier.ctrl);
  final hasAlt = modifiers.contains(TerminalShortcutModifier.alt);
  final hasShift = modifiers.contains(TerminalShortcutModifier.shift);
  if (key == 'tab') {
    if (hasShift && !hasCtrl && !hasAlt) {
      return <int>[_esc, 0x5b, 0x5a];
    }
    return _withAltPrefix(<int>[0x09], hasAlt);
  }
  if (key == 'escape') {
    return _withAltPrefix(<int>[_esc], hasAlt);
  }
  if (key == 'enter') {
    return _withAltPrefix(<int>[0x0d], hasAlt);
  }
  if (key == 'backspace') {
    return _withAltPrefix(<int>[hasCtrl ? 0x08 : 0x7f], hasAlt);
  }
  if (_isPrintableShortcutKey(key)) {
    return _buildPrintableShortcutBytes(key, modifiers);
  }
  return null;
}

List<int>? _buildPrintableShortcutBytes(
  String key,
  Set<TerminalShortcutModifier> modifiers,
) {
  final shifted = modifiers.contains(TerminalShortcutModifier.shift)
      ? _applyShift(key)
      : key;
  List<int> bytes = shifted.codeUnits;
  if (modifiers.contains(TerminalShortcutModifier.ctrl)) {
    final ctrlByte = _controlByteForPrintable(shifted);
    if (ctrlByte == null) {
      return null;
    }
    bytes = <int>[ctrlByte];
  }
  return _withAltPrefix(
    bytes,
    modifiers.contains(TerminalShortcutModifier.alt),
  );
}

List<int> _withAltPrefix(List<int> bytes, bool alt) {
  return alt ? <int>[_esc, ...bytes] : bytes;
}

List<int> _buildCsiFinalShortcut(
  int finalByte,
  Set<TerminalShortcutModifier> modifiers,
) {
  final parameter = _csiModifierParameter(modifiers);
  if (parameter == 1) {
    return <int>[_esc, 0x5b, finalByte];
  }
  return <int>[_esc, 0x5b, 0x31, 0x3b, ...'$parameter'.codeUnits, finalByte];
}

List<int> _buildCsiTildeShortcut(
  int code,
  Set<TerminalShortcutModifier> modifiers,
) {
  final parameter = _csiModifierParameter(modifiers);
  if (parameter == 1) {
    return <int>[_esc, 0x5b, ...'$code'.codeUnits, 0x7e];
  }
  return <int>[
    _esc,
    0x5b,
    ...'$code'.codeUnits,
    0x3b,
    ...'$parameter'.codeUnits,
    0x7e,
  ];
}

int _csiModifierParameter(Set<TerminalShortcutModifier> modifiers) {
  var parameter = 1;
  if (modifiers.contains(TerminalShortcutModifier.shift)) {
    parameter += 1;
  }
  if (modifiers.contains(TerminalShortcutModifier.alt)) {
    parameter += 2;
  }
  if (modifiers.contains(TerminalShortcutModifier.ctrl)) {
    parameter += 4;
  }
  return parameter;
}

int? _controlByteForPrintable(String key) {
  final lower = key.toLowerCase();
  final code = lower.codeUnitAt(0);
  if (code >= 0x61 && code <= 0x7a) {
    return code - 96;
  }
  return _ctrlPrintableBytes[key];
}

String _applyShift(String key) {
  final code = key.codeUnitAt(0);
  if (code >= 0x61 && code <= 0x7a) {
    return key.toUpperCase();
  }
  if (code >= 0x41 && code <= 0x5a) {
    return key;
  }
  return _shiftedPrintable[key] ?? key;
}

String? _normalizeShortcutKey(String key) {
  if (_specialKeyLabels.containsKey(key)) {
    return key;
  }
  if (_isPrintableShortcutKey(key)) {
    final code = key.codeUnitAt(0);
    return code >= 0x41 && code <= 0x5a ? key.toLowerCase() : key;
  }
  return null;
}

bool _isPrintableShortcutKey(String key) {
  if (key.length != 1) {
    return false;
  }
  final code = key.codeUnitAt(0);
  return code >= 0x20 && code <= 0x7e;
}

String _formatShortcutLabel(
  String key,
  Set<TerminalShortcutModifier> modifiers,
) {
  final parts = <String>[
    if (modifiers.contains(TerminalShortcutModifier.ctrl)) 'Ctrl',
    if (modifiers.contains(TerminalShortcutModifier.alt)) 'Alt',
    if (modifiers.contains(TerminalShortcutModifier.shift)) 'Shift',
    _displayKeyLabel(key),
  ];
  return parts.join('+');
}

String _displayKeyLabel(String key) {
  final special = _specialKeyLabels[key];
  if (special != null) {
    return special;
  }
  if (key == ' ') {
    return 'Space';
  }
  final code = key.codeUnitAt(0);
  return code >= 0x61 && code <= 0x7a ? key.toUpperCase() : key;
}
