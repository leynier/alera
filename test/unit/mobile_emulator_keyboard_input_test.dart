import 'package:alera/src/features/mobile_emulator/presentation/mobile_emulator_keyboard_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts printable text and preserves shifted characters', () {
    expect(
      mobileEmulatorPrintableText(
        character: 'A',
        controlPressed: false,
        metaPressed: false,
        altPressed: false,
      ),
      'A',
    );
    expect(
      mobileEmulatorPrintableText(
        character: '🙂',
        controlPressed: false,
        metaPressed: false,
        altPressed: false,
      ),
      '🙂',
    );
  });

  test('leaves command shortcuts and control characters unhandled', () {
    for (final modifiers in <({bool control, bool meta, bool alt})>[
      (control: true, meta: false, alt: false),
      (control: false, meta: true, alt: false),
      (control: false, meta: false, alt: true),
    ]) {
      expect(
        mobileEmulatorPrintableText(
          character: 'w',
          controlPressed: modifiers.control,
          metaPressed: modifiers.meta,
          altPressed: modifiers.alt,
        ),
        isNull,
      );
    }
    expect(
      mobileEmulatorPrintableText(
        character: '\n',
        controlPressed: false,
        metaPressed: false,
        altPressed: false,
      ),
      isNull,
    );
  });

  test('maps unmodified form and navigation keys for the emulator', () {
    final expected = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.enter: 'enter',
      LogicalKeyboardKey.numpadEnter: 'enter',
      LogicalKeyboardKey.backspace: 'backspace',
      LogicalKeyboardKey.tab: 'tab',
      LogicalKeyboardKey.delete: 'deleteForward',
      LogicalKeyboardKey.arrowUp: 'arrowUp',
      LogicalKeyboardKey.arrowDown: 'arrowDown',
      LogicalKeyboardKey.arrowLeft: 'arrowLeft',
      LogicalKeyboardKey.arrowRight: 'arrowRight',
      LogicalKeyboardKey.escape: 'escape',
    };
    for (final entry in expected.entries) {
      expect(
        mobileEmulatorInteractiveKey(
          logicalKey: entry.key,
          controlPressed: false,
          metaPressed: false,
          altPressed: false,
          shiftPressed: false,
        ),
        entry.value,
      );
    }
  });

  test('leaves modified and unsupported keys to Alera shortcuts', () {
    for (final modifiers in <({bool control, bool meta, bool alt, bool shift})>[
      (control: true, meta: false, alt: false, shift: false),
      (control: false, meta: true, alt: false, shift: false),
      (control: false, meta: false, alt: true, shift: false),
      (control: false, meta: false, alt: false, shift: true),
    ]) {
      expect(
        mobileEmulatorInteractiveKey(
          logicalKey: LogicalKeyboardKey.enter,
          controlPressed: modifiers.control,
          metaPressed: modifiers.meta,
          altPressed: modifiers.alt,
          shiftPressed: modifiers.shift,
        ),
        isNull,
      );
    }
    expect(
      mobileEmulatorInteractiveKey(
        logicalKey: LogicalKeyboardKey.f1,
        controlPressed: false,
        metaPressed: false,
        altPressed: false,
        shiftPressed: false,
      ),
      isNull,
    );
  });
}
