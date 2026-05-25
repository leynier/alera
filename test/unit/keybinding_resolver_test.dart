import 'package:alera/src/features/keyboard/application/keybinding_resolver.dart';
import 'package:alera/src/features/keyboard/domain/key_chord.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_shortcut_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

KeyDownEvent _down(LogicalKeyboardKey key) {
  return KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.keyT,
    logicalKey: key,
    timeStamp: Duration.zero,
  );
}

void main() {
  group('registry integrity', () {
    test('every default binding parses', () {
      for (final definition in keybindingDefinitions) {
        for (final platform in KeyboardPlatform.values) {
          for (final binding in definition.defaultBindings.forPlatform(platform)) {
            expect(
              KeyChord.parse(binding),
              isA<KeyChordParseSuccess>(),
              reason: '${definition.id.name} -> "$binding" on ${platform.name}',
            );
          }
        }
      }
    });

    test('no two actions share a default chord on any platform', () {
      for (final platform in KeyboardPlatform.values) {
        final resolver = KeybindingResolver(
          settings: KeyboardShortcutSettings.defaults,
          platform: platform,
        );
        final seen = <KeyChord, KeyboardActionId>{};
        for (final definition in keybindingDefinitions) {
          for (final chord in resolver.effectiveChords(definition.id)) {
            final previous = seen[chord];
            expect(
              previous,
              isNull,
              reason:
                  'on ${platform.name} ${definition.id.name} and '
                  '${previous?.name} both bind ${chord.toCanonicalString()}',
            );
            seen[chord] = definition.id;
          }
        }
      }
    });
  });

  group('effectiveChords', () {
    test('falls back to the platform default', () {
      final resolver = KeybindingResolver(
        settings: KeyboardShortcutSettings.defaults,
        platform: KeyboardPlatform.macos,
      );
      expect(
        resolver.effectiveChords(KeyboardActionId.newTerminalTab).single
            .toCanonicalString(),
        'Mod+T',
      );
    });

    test('uses the user override when present', () {
      final settings = KeyboardShortcutSettings.defaults
          .copyWithOverride(KeyboardActionId.newTerminalTab, <String>['Mod+Shift+T']);
      final resolver = KeybindingResolver(
        settings: settings,
        platform: KeyboardPlatform.linux,
      );
      expect(
        resolver.effectiveChords(KeyboardActionId.newTerminalTab).single
            .toCanonicalString(),
        'Mod+Shift+T',
      );
    });

    test('returns empty for a disabled action', () {
      final settings = KeyboardShortcutSettings.defaults
          .copyWithOverride(KeyboardActionId.newTerminalTab, const <String>[]);
      final resolver = KeybindingResolver(
        settings: settings,
        platform: KeyboardPlatform.linux,
      );
      expect(resolver.effectiveChords(KeyboardActionId.newTerminalTab), isEmpty);
    });
  });

  group('resolveAction', () {
    test('matches the right action on macOS', () {
      final resolver = KeybindingResolver(
        settings: KeyboardShortcutSettings.defaults,
        platform: KeyboardPlatform.macos,
      );
      final resolved = resolver.resolveAction(
        _down(LogicalKeyboardKey.keyT),
        const KeyModifierState(meta: true),
      );
      expect(resolved?.id, KeyboardActionId.newTerminalTab);
    });

    test('does not match when a modifier is missing', () {
      final resolver = KeybindingResolver(
        settings: KeyboardShortcutSettings.defaults,
        platform: KeyboardPlatform.macos,
      );
      final resolved = resolver.resolveAction(
        _down(LogicalKeyboardKey.keyT),
        const KeyModifierState(),
      );
      expect(resolved, isNull);
    });

    test('ignores a disabled binding', () {
      final settings = KeyboardShortcutSettings.defaults
          .copyWithOverride(KeyboardActionId.newTerminalTab, const <String>[]);
      final resolver = KeybindingResolver(
        settings: settings,
        platform: KeyboardPlatform.macos,
      );
      final resolved = resolver.resolveAction(
        _down(LogicalKeyboardKey.keyT),
        const KeyModifierState(meta: true),
      );
      expect(resolved, isNull);
    });
  });

  group('findConflict', () {
    test('detects a chord already used by another action', () {
      final resolver = KeybindingResolver(
        settings: KeyboardShortcutSettings.defaults,
        platform: KeyboardPlatform.macos,
      );
      // Mod+T belongs to newTerminalTab; assigning it to closeTab conflicts.
      final chord =
          (KeyChord.parse('Mod+T') as KeyChordParseSuccess).chord;
      expect(
        resolver.findConflict(chord, excluding: KeyboardActionId.closeTab),
        KeyboardActionId.newTerminalTab,
      );
    });

    test('excludes the action being edited', () {
      final resolver = KeybindingResolver(
        settings: KeyboardShortcutSettings.defaults,
        platform: KeyboardPlatform.macos,
      );
      final chord =
          (KeyChord.parse('Mod+T') as KeyChordParseSuccess).chord;
      expect(
        resolver.findConflict(chord, excluding: KeyboardActionId.newTerminalTab),
        isNull,
      );
    });

    test('returns null for a free chord', () {
      final resolver = KeybindingResolver(
        settings: KeyboardShortcutSettings.defaults,
        platform: KeyboardPlatform.macos,
      );
      final chord =
          (KeyChord.parse('Mod+Shift+J') as KeyChordParseSuccess).chord;
      expect(
        resolver.findConflict(chord, excluding: KeyboardActionId.closeTab),
        isNull,
      );
    });
  });
}
