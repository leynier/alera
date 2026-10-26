import 'package:alera/src/features/keyboard/application/keybinding_resolver.dart';
import 'package:alera/src/features/keyboard/domain/key_chord.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_shortcut_settings.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

KeyDownEvent _down(LogicalKeyboardKey key) {
  return KeyDownEvent(physicalKey: .keyT, logicalKey: key, timeStamp: .zero);
}

void main() {
  group('registry integrity', () {
    test('every default binding parses', () {
      for (final definition in keybindingDefinitions) {
        for (final platform in KeyboardPlatform.values) {
          for (final binding in definition.defaultBindings.forPlatform(
            platform,
          )) {
            expect(
              KeyChord.parse(binding),
              isA<KeyChordParseSuccess>(),
              reason: '${definition.id.name} -> "$binding" on ${platform.name}',
            );
          }
        }
      }
    });

    test('no two actions of a scope share a default chord on any platform', () {
      for (final platform in KeyboardPlatform.values) {
        final resolver = KeybindingResolver(
          settings: .defaults,
          platform: platform,
        );
        final seen = <(KeyboardActionScope, KeyChord), KeyboardActionId>{};
        for (final definition in keybindingDefinitions) {
          for (final chord in resolver.effectiveChords(definition.id)) {
            final previous = seen[(definition.scope, chord)];
            expect(
              previous,
              isNull,
              reason:
                  'on ${platform.name} ${definition.id.name} and '
                  '${previous?.name} both bind ${chord.toCanonicalString()}',
            );
            seen[(definition.scope, chord)] = definition.id;
          }
        }
      }
    });
  });

  group('effectiveChords', () {
    test('falls back to the platform default', () {
      final resolver = KeybindingResolver(
        settings: .defaults,
        platform: .macos,
      );
      expect(
        resolver.effectiveChords(.newTerminalTab).single.toCanonicalString(),
        'Mod+T',
      );
    });

    test('uses the user override when present', () {
      final settings = KeyboardShortcutSettings.defaults.copyWithOverride(
        .newTerminalTab,
        <String>['Mod+Shift+T'],
      );
      final resolver = KeybindingResolver(settings: settings, platform: .linux);
      expect(
        resolver.effectiveChords(.newTerminalTab).single.toCanonicalString(),
        'Mod+Shift+T',
      );
    });

    test('returns empty for a disabled action', () {
      final settings = KeyboardShortcutSettings.defaults.copyWithOverride(
        .newTerminalTab,
        const <String>[],
      );
      final resolver = KeybindingResolver(settings: settings, platform: .linux);
      expect(resolver.effectiveChords(.newTerminalTab), isEmpty);
    });

    test('uses platform-correct worktree navigation defaults', () {
      final macResolver = KeybindingResolver(
        settings: .defaults,
        platform: .macos,
      );
      final desktopResolver = KeybindingResolver(
        settings: .defaults,
        platform: .windows,
      );

      expect(
        macResolver.effectiveChords(.navigateBack).single.toCanonicalString(),
        'Mod+BracketLeft',
      );
      expect(
        desktopResolver
            .effectiveChords(.navigateForward)
            .single
            .toCanonicalString(),
        'Alt+ArrowRight',
      );
    });
  });

  test('worktree navigation remains terminal-first safe', () {
    expect(
      keybindingDefinitionsById[KeyboardActionId.navigateBack]!.allowInTerminal,
      isFalse,
    );
    expect(
      keybindingDefinitionsById[KeyboardActionId.navigateForward]!
          .allowInTerminal,
      isFalse,
    );
  });

  test(
    'quick open and command palette have distinct terminal-safe defaults',
    () {
      final resolver = KeybindingResolver(
        settings: .defaults,
        platform: .macos,
      );

      expect(
        resolver.effectiveChords(.openQuickOpen).single.toCanonicalString(),
        'Mod+P',
      );
      expect(
        resolver
            .effectiveChords(.openCommandPalette)
            .single
            .toCanonicalString(),
        'Mod+Shift+P',
      );
      expect(
        keybindingDefinitionsById[KeyboardActionId.openQuickOpen]!
            .allowInTerminal,
        isTrue,
      );
      expect(
        keybindingDefinitionsById[KeyboardActionId.openCommandPalette]!
            .allowInTerminal,
        isTrue,
      );
    },
  );

  group('resolveAction', () {
    test('matches the right action on macOS', () {
      final resolver = KeybindingResolver(
        settings: .defaults,
        platform: .macos,
      );
      final resolved = resolver.resolveAction(
        _down(.keyT),
        const KeyModifierState(meta: true),
      );
      expect(resolved?.id, KeyboardActionId.newTerminalTab);
    });

    test('does not match when a modifier is missing', () {
      final resolver = KeybindingResolver(
        settings: .defaults,
        platform: .macos,
      );
      final resolved = resolver.resolveAction(
        _down(.keyT),
        const KeyModifierState(),
      );
      expect(resolved, isNull);
    });

    test('Mod+F finds in a focused chat and in the terminal elsewhere', () {
      final resolver = KeybindingResolver(
        settings: .defaults,
        platform: .linux,
      );
      const control = KeyModifierState(control: true);
      expect(
        resolver.resolveAction(_down(.keyF), control)?.id,
        KeyboardActionId.findInTerminal,
      );
      expect(
        resolver
            .resolveAction(_down(.keyF), control, focusScope: .agentChat)
            ?.id,
        KeyboardActionId.findInAgentChat,
      );
      // Global bindings still work inside a chat.
      expect(
        resolver
            .resolveAction(_down(.keyT), control, focusScope: .agentChat)
            ?.id,
        KeyboardActionId.newTerminalTab,
      );
    });

    test('ignores a disabled binding', () {
      final settings = KeyboardShortcutSettings.defaults.copyWithOverride(
        .newTerminalTab,
        const <String>[],
      );
      final resolver = KeybindingResolver(settings: settings, platform: .macos);
      final resolved = resolver.resolveAction(
        _down(.keyT),
        const KeyModifierState(meta: true),
      );
      expect(resolved, isNull);
    });
  });

  group('findConflict', () {
    test('detects a chord already used by another action', () {
      final resolver = KeybindingResolver(
        settings: .defaults,
        platform: .macos,
      );
      // Mod+T belongs to newTerminalTab; assigning it to closeTab conflicts.
      final chord = (KeyChord.parse('Mod+T') as KeyChordParseSuccess).chord;
      expect(
        resolver.findConflict(chord, excluding: .closeTab),
        KeyboardActionId.newTerminalTab,
      );
    });

    test('excludes the action being edited', () {
      final resolver = KeybindingResolver(
        settings: .defaults,
        platform: .macos,
      );
      final chord = (KeyChord.parse('Mod+T') as KeyChordParseSuccess).chord;
      expect(resolver.findConflict(chord, excluding: .newTerminalTab), isNull);
    });

    test('a chat binding sharing a global chord is not a conflict', () {
      final resolver = KeybindingResolver(
        settings: .defaults,
        platform: .macos,
      );
      final chord = (KeyChord.parse('Mod+F') as KeyChordParseSuccess).chord;
      expect(resolver.findConflict(chord, excluding: .findInAgentChat), isNull);
      expect(
        resolver.findConflict(chord, excluding: .closeTab),
        KeyboardActionId.findInTerminal,
      );
    });

    test('returns null for a free chord', () {
      final resolver = KeybindingResolver(
        settings: .defaults,
        platform: .macos,
      );
      final chord =
          (KeyChord.parse('Mod+Shift+J') as KeyChordParseSuccess).chord;
      expect(resolver.findConflict(chord, excluding: .closeTab), isNull);
    });
  });
}
