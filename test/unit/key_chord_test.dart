import 'package:alera/src/features/keyboard/domain/key_chord.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

KeyChord _parse(String value) {
  final result = KeyChord.parse(value);
  if (result is! KeyChordParseSuccess) {
    throw StateError('expected "$value" to parse, got $result');
  }
  return result.chord;
}

void main() {
  group('KeyChord.parse', () {
    test('round-trips canonical strings', () {
      const inputs = <String>[
        'Mod+P',
        'Mod+Shift+BracketRight',
        'Ctrl+Tab',
        'Mod+1',
        'Mod+Comma',
        'Mod+Alt+D',
      ];
      for (final input in inputs) {
        expect(_parse(input).toCanonicalString(), input);
      }
    });

    test('normalizes symbol aliases to canonical tokens', () {
      expect(_parse('Mod+,').toCanonicalString(), 'Mod+Comma');
      expect(
        _parse('Mod+Shift+]').toCanonicalString(),
        'Mod+Shift+BracketRight',
      );
      expect(_parse('Mod+[').toCanonicalString(), 'Mod+BracketLeft');
    });

    test('is case-insensitive for modifiers', () {
      expect(_parse('mod+shift+p').toCanonicalString(), 'Mod+Shift+P');
      expect(_parse('CTRL+t').toCanonicalString(), 'Ctrl+T');
    });

    test('rejects a chord with no modifier', () {
      expect(KeyChord.parse('P'), isA<KeyChordParseFailure>());
    });

    test('allows bare function keys', () {
      expect(KeyChord.parse('F5'), isA<KeyChordParseSuccess>());
    });

    test('rejects Mod combined with a platform modifier', () {
      expect(KeyChord.parse('Mod+Ctrl+P'), isA<KeyChordParseFailure>());
    });

    test('rejects unsupported trigger tokens', () {
      final result = KeyChord.parse('Mod+LaunchRocket');

      expect(result, isA<KeyChordParseFailure>());
      expect(
        (result as KeyChordParseFailure).message,
        'Unsupported key: LaunchRocket.',
      );
    });

    test('rejects two trigger keys', () {
      expect(KeyChord.parse('Mod+P+Q'), isA<KeyChordParseFailure>());
    });

    test('rejects empty input', () {
      expect(KeyChord.parse('   '), isA<KeyChordParseFailure>());
    });
  });

  group('KeyChord.format', () {
    test('uses glyphs on macOS', () {
      expect(_parse('Mod+Shift+P').format(isMacOS: true), '⇧⌘P');
      expect(_parse('Mod+Comma').format(isMacOS: true), '⌘,');
      expect(_parse('Ctrl+Alt+T').format(isMacOS: true), '⌃⌥T');
    });

    test('uses words on other platforms', () {
      expect(_parse('Mod+Shift+P').format(isMacOS: false), 'Ctrl+Shift+P');
      expect(_parse('Mod+Comma').format(isMacOS: false), 'Ctrl+,');
      expect(
        _parse('Mod+Shift+BracketRight').format(isMacOS: false),
        'Ctrl+Shift+]',
      );
    });
  });

  group('KeyChord.matches', () {
    final modP = _parse('Mod+P');

    KeyDownEvent down(LogicalKeyboardKey key) {
      return KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyP,
        logicalKey: key,
        timeStamp: Duration.zero,
      );
    }

    test('Mod resolves to Meta on macOS', () {
      expect(
        modP.matches(
          down(LogicalKeyboardKey.keyP),
          const KeyModifierState(meta: true),
          isMacOS: true,
        ),
        isTrue,
      );
      // Control should not satisfy Mod on macOS.
      expect(
        modP.matches(
          down(LogicalKeyboardKey.keyP),
          const KeyModifierState(control: true),
          isMacOS: true,
        ),
        isFalse,
      );
    });

    test('Mod resolves to Control off macOS', () {
      expect(
        modP.matches(
          down(LogicalKeyboardKey.keyP),
          const KeyModifierState(control: true),
          isMacOS: false,
        ),
        isTrue,
      );
    });

    test('requires exact modifier set', () {
      // Extra Shift must not match a plain Mod+P.
      expect(
        modP.matches(
          down(LogicalKeyboardKey.keyP),
          const KeyModifierState(meta: true, shift: true),
          isMacOS: true,
        ),
        isFalse,
      );
    });

    test('ignores key-up events', () {
      final up = KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.keyP,
        logicalKey: LogicalKeyboardKey.keyP,
        timeStamp: Duration.zero,
      );
      expect(
        modP.matches(up, const KeyModifierState(meta: true), isMacOS: true),
        isFalse,
      );
    });
  });

  group('KeyChord.fromKeyEvent', () {
    KeyDownEvent down(LogicalKeyboardKey key) {
      return KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyT,
        logicalKey: key,
        timeStamp: Duration.zero,
      );
    }

    test('collapses platform modifier into Mod', () {
      final macResult = KeyChord.fromKeyEvent(
        down(LogicalKeyboardKey.keyT),
        const KeyModifierState(meta: true),
        isMacOS: true,
      );
      expect(
        (macResult as KeyChordParseSuccess).chord.toCanonicalString(),
        'Mod+T',
      );

      final linuxResult = KeyChord.fromKeyEvent(
        down(LogicalKeyboardKey.keyT),
        const KeyModifierState(control: true),
        isMacOS: false,
      );
      expect(
        (linuxResult as KeyChordParseSuccess).chord.toCanonicalString(),
        'Mod+T',
      );
    });

    test('rejects a lone modifier press', () {
      final event = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.metaLeft,
        logicalKey: LogicalKeyboardKey.metaLeft,
        timeStamp: Duration.zero,
      );
      expect(
        KeyChord.fromKeyEvent(event, const KeyModifierState(), isMacOS: true),
        isA<KeyChordParseFailure>(),
      );
    });

    test('rejects an unmodified letter', () {
      expect(
        KeyChord.fromKeyEvent(
          down(LogicalKeyboardKey.keyT),
          const KeyModifierState(),
          isMacOS: true,
        ),
        isA<KeyChordParseFailure>(),
      );
    });
  });

  group('KeyChord equality', () {
    test('equal chords share identity and hash', () {
      expect(_parse('Mod+Shift+P'), _parse('Mod+Shift+P'));
      expect(_parse('Mod+Shift+P').hashCode, _parse('Mod+Shift+P').hashCode);
      expect(_parse('Mod+Shift+P'), isNot(_parse('Mod+P')));
    });

    test('toString and fallback display labels stay readable', () {
      final chord = KeyChord(
        trigger: LogicalKeyboardKey.audioVolumeUp,
        control: true,
      );

      expect(chord.toString(), 'KeyChord(Ctrl+Audio Volume Up)');
      expect(chord.format(isMacOS: false), 'Ctrl+Audio Volume Up');
    });
  });
}
