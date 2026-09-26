import 'package:alera/src/features/keyboard/domain/key_chord.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Run Board is global and has no default shortcut on any platform', () {
    final action = keybindingDefinitions.singleWhere(
      (item) => item.id == KeyboardActionId.openRunBoard,
    );
    expect(action.group, KeyboardActionGroup.global);
    expect(action.allowInTerminal, isTrue);
    for (final platform in KeyboardPlatform.values) {
      expect(action.defaultBindings.forPlatform(platform), isEmpty);
    }
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('KeyboardPlatform.current follows the active target platform', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(KeyboardPlatform.current, KeyboardPlatform.macos);
    expect(KeyboardPlatform.current.isMacOS, isTrue);

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    expect(KeyboardPlatform.current, KeyboardPlatform.windows);
    expect(KeyboardPlatform.current.isMacOS, isFalse);

    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(KeyboardPlatform.current, KeyboardPlatform.linux);
  });

  test('PlatformBindings.forPlatform returns the configured bindings', () {
    const bindings = PlatformBindings(
      macos: <String>['Meta+K'],
      windows: <String>['Ctrl+K'],
      linux: <String>['Ctrl+Shift+K'],
    );

    expect(bindings.forPlatform(.macos), <String>['Meta+K']);
    expect(bindings.forPlatform(.windows), <String>['Ctrl+K']);
    expect(bindings.forPlatform(.linux), <String>['Ctrl+Shift+K']);
  });

  test('KeyboardActionId.tabIndex only applies to go-to-tab actions', () {
    expect(KeyboardActionId.goToTab1.tabIndex, 1);
    expect(KeyboardActionId.goToTab5.tabIndex, 5);
    expect(KeyboardActionId.goToTab9.tabIndex, 9);
    expect(KeyboardActionId.closeTab.tabIndex, isNull);
  });

  test('every action has exactly one definition', () {
    final ids = keybindingDefinitions.map((definition) => definition.id);
    expect(ids.toSet(), KeyboardActionId.values.toSet());
    expect(ids.length, KeyboardActionId.values.length);
  });

  test('default chords parse and stay unique per platform', () {
    for (final platform in KeyboardPlatform.values) {
      final owners = <String, KeyboardActionId>{};
      for (final definition in keybindingDefinitions) {
        for (final binding in definition.defaultBindings.forPlatform(
          platform,
        )) {
          final result = KeyChord.parse(binding);
          expect(
            result,
            isA<KeyChordParseSuccess>(),
            reason: '${definition.id.name} on ${platform.name}: $binding',
          );
          final chord = (result as KeyChordParseSuccess).chord;
          final isMacOS = platform.isMacOS;
          final resolved = <Object>[
            chord.meta || (chord.useMod && isMacOS),
            chord.control || (chord.useMod && !isMacOS),
            chord.alt,
            chord.shift,
            chord.trigger.keyId,
          ].join(':');
          final owner = owners.putIfAbsent(resolved, () => definition.id);
          expect(
            owner,
            definition.id,
            reason:
                '$binding on ${platform.name} is bound to both ${owner.name} '
                'and ${definition.id.name}',
          );
        }
      }
    }
  });
}
