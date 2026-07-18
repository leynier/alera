import 'package:alera_mobile/src/features/terminal/domain/terminal_shortcut_builder.dart';
import 'package:flutter_test/flutter_test.dart';

List<int>? bytesFor(String key, [Set<TerminalShortcutModifier>? modifiers]) {
  return buildTerminalShortcutKey(
    TerminalShortcutBinding(
      key: key,
      modifiers: modifiers ?? const <TerminalShortcutModifier>{},
    ),
  )?.bytes;
}

void main() {
  const ctrl = TerminalShortcutModifier.ctrl;
  const alt = TerminalShortcutModifier.alt;
  const shift = TerminalShortcutModifier.shift;

  test('Encodes control letters with ctrl arithmetic', () {
    expect(bytesFor('c', <TerminalShortcutModifier>{ctrl}), <int>[0x03]);
    expect(bytesFor('a', <TerminalShortcutModifier>{ctrl}), <int>[0x01]);
    expect(bytesFor('z', <TerminalShortcutModifier>{ctrl}), <int>[0x1a]);
  });

  test('Encodes ctrl punctuation through the printable table', () {
    expect(bytesFor('space', <TerminalShortcutModifier>{ctrl}), <int>[0x00]);
    expect(bytesFor('[', <TerminalShortcutModifier>{ctrl}), <int>[0x1b]);
    expect(bytesFor('?', <TerminalShortcutModifier>{ctrl}), <int>[0x7f]);
  });

  test('Alt prefixes with escape', () {
    expect(bytesFor('x', <TerminalShortcutModifier>{alt}), <int>[0x1b, 0x78]);
    expect(bytesFor('c', <TerminalShortcutModifier>{ctrl, alt}), <int>[
      0x1b,
      0x03,
    ]);
  });

  test('Shift maps printables through the shifted table', () {
    expect(bytesFor('2', <TerminalShortcutModifier>{shift}), '@'.codeUnits);
    expect(bytesFor('a', <TerminalShortcutModifier>{shift}), 'A'.codeUnits);
    // Ctrl applies to the shifted character: Ctrl+Shift+2 = Ctrl+@ = NUL.
    expect(bytesFor('2', <TerminalShortcutModifier>{ctrl, shift}), <int>[0x00]);
  });

  test('Shift Tab is the reverse-tab CSI Z sequence', () {
    expect(bytesFor('tab', <TerminalShortcutModifier>{shift}), <int>[
      0x1b,
      0x5b,
      0x5a,
    ]);
    expect(bytesFor('tab'), <int>[0x09]);
  });

  test('Arrows use CSI with the 1;N modifier parameter', () {
    expect(bytesFor('arrowUp'), <int>[0x1b, 0x5b, 0x41]);
    expect(
      bytesFor('arrowUp', <TerminalShortcutModifier>{ctrl, shift}),
      '\x1b[1;6A'.codeUnits,
    );
    expect(
      bytesFor('arrowLeft', <TerminalShortcutModifier>{alt}),
      '\x1b[1;3D'.codeUnits,
    );
  });

  test('F1 through F4 use SS3 unmodified and CSI when modified', () {
    expect(bytesFor('f1'), <int>[0x1b, 0x4f, 0x50]);
    expect(
      bytesFor('f1', <TerminalShortcutModifier>{shift}),
      '\x1b[1;2P'.codeUnits,
    );
  });

  test('Tilde special keys carry the modifier parameter', () {
    expect(bytesFor('delete'), '\x1b[3~'.codeUnits);
    expect(
      bytesFor('delete', <TerminalShortcutModifier>{ctrl}),
      '\x1b[3;5~'.codeUnits,
    );
    expect(bytesFor('pageUp'), '\x1b[5~'.codeUnits);
    expect(bytesFor('f12'), '\x1b[24~'.codeUnits);
  });

  test('Ctrl backspace sends BS and alt prefixes it', () {
    expect(bytesFor('backspace'), <int>[0x7f]);
    expect(bytesFor('backspace', <TerminalShortcutModifier>{ctrl}), <int>[
      0x08,
    ]);
    expect(bytesFor('backspace', <TerminalShortcutModifier>{ctrl, alt}), <int>[
      0x1b,
      0x08,
    ]);
  });

  test('Labels are ordered Ctrl Alt Shift and uppercase letters', () {
    final result = buildTerminalShortcutKey(
      const TerminalShortcutBinding(
        key: 'k',
        modifiers: <TerminalShortcutModifier>{shift, ctrl, alt},
      ),
    );
    expect(result!.label, 'Ctrl+Alt+Shift+K');
    expect(result.accessibilityLabel, 'Ctrl Alt Shift K');
  });

  test('Rejects unbuildable bindings', () {
    expect(bytesFor(''), isNull);
    expect(bytesFor('nope'), isNull);
    expect(bytesFor('é'), isNull);
  });
}
