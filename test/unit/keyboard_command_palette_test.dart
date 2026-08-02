import 'package:alera/src/features/keyboard/domain/keyboard_action.dart';
import 'package:alera/src/features/keyboard/domain/keyboard_command_palette.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty query returns the complete central command registry', () {
    final matches = filterKeyboardCommandPalette('');

    expect(matches.length, keybindingDefinitions.length);
    expect(matches.first.definition.id, KeyboardActionId.addProject);
  });

  test('filters labels and keywords case insensitively', () {
    final matches = filterKeyboardCommandPalette('QUICK');

    expect(matches.map((match) => match.definition.id), <KeyboardActionId>[
      KeyboardActionId.openQuickOpen,
    ]);
  });

  test('label matches outrank keyword matches', () {
    final matches = filterKeyboardCommandPalette('command');

    expect(matches.first.definition.id, KeyboardActionId.openCommandPalette);
  });

  test(
    'keyword prefixes, contains matches, and fuzzy labels are searchable',
    () {
      expect(
        filterKeyboardCommandPalette('act').first.definition.id,
        KeyboardActionId.openCommandPalette,
      );
      expect(
        filterKeyboardCommandPalette('tions').first.definition.id,
        KeyboardActionId.openCommandPalette,
      );
      expect(
        filterKeyboardCommandPalette('dialog').first.definition.id,
        KeyboardActionId.openSettings,
      );
      expect(
        filterKeyboardCommandPalette('cmdp').first.definition.id,
        KeyboardActionId.openCommandPalette,
      );
    },
  );

  test('identical labels use the stable action id as a tie breaker', () {
    final definitions = <KeybindingDefinition>[
      const KeybindingDefinition(
        id: KeyboardActionId.openSettings,
        label: 'Same Action',
        group: KeyboardActionGroup.global,
        description: 'First.',
        defaultBindings: PlatformBindings.uniform(<String>['Mod+1']),
      ),
      const KeybindingDefinition(
        id: KeyboardActionId.addProject,
        label: 'Same Action',
        group: KeyboardActionGroup.global,
        description: 'Second.',
        defaultBindings: PlatformBindings.uniform(<String>['Mod+2']),
      ),
    ];

    final matches = filterKeyboardCommandPalette(
      'same action',
      definitions: definitions,
    );

    expect(matches.map((match) => match.definition.id), <KeyboardActionId>[
      KeyboardActionId.addProject,
      KeyboardActionId.openSettings,
    ]);
  });

  test('command results are bounded with stable label ordering', () {
    final definitions = <KeybindingDefinition>[
      const KeybindingDefinition(
        id: KeyboardActionId.openSettings,
        label: 'Alpha Action',
        group: KeyboardActionGroup.global,
        description: 'Run the same command.',
        defaultBindings: PlatformBindings.uniform(<String>['Mod+1']),
        searchKeywords: <String>['shared'],
      ),
      const KeybindingDefinition(
        id: KeyboardActionId.addProject,
        label: 'Beta Action',
        group: KeyboardActionGroup.global,
        description: 'Run the same command.',
        defaultBindings: PlatformBindings.uniform(<String>['Mod+2']),
        searchKeywords: <String>['shared'],
      ),
      const KeybindingDefinition(
        id: KeyboardActionId.toggleSidebar,
        label: 'Gamma Action',
        group: KeyboardActionGroup.global,
        description: 'Run the same command.',
        defaultBindings: PlatformBindings.uniform(<String>['Mod+3']),
        searchKeywords: <String>['shared'],
      ),
    ];

    final matches = filterKeyboardCommandPalette(
      'shared',
      definitions: definitions,
      limit: 2,
    );

    expect(matches.length, 2);
    expect(matches.map((match) => match.definition.label), <String>[
      'Alpha Action',
      'Beta Action',
    ]);
  });
}
