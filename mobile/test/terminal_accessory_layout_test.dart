import 'package:alera_mobile/src/features/terminal/domain/terminal_accessory_key.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_accessory_layout.dart';
import 'package:alera_mobile/src/features/terminal/domain/terminal_shortcut_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Round-trips through json preserving order and visibility', () {
    final layout = TerminalAccessoryLayout.defaults().copyWith(
      hiddenIds: <String>{'space'},
      customKeys: <TerminalCustomKey>[
        const TerminalCustomKey(
          id: 'custom-1',
          key: 'k',
          modifiers: <TerminalShortcutModifier>{TerminalShortcutModifier.ctrl},
        ),
      ],
    );
    final restored = TerminalAccessoryLayout.fromJson(layout.toJson());

    expect(restored.hiddenIds, <String>{'space'});
    expect(restored.customKeys.single.key, 'k');
    expect(
      restored.orderedIds.length,
      greaterThanOrEqualTo(builtInTerminalAccessoryKeys.length),
    );
  });

  test('Drops unknown ids at load time', () {
    final layout = TerminalAccessoryLayout.fromJson(<String, Object?>{
      'version': 1,
      'orderedIds': <String>['escape', 'removed-key', 'tab'],
      'hiddenIds': <String>['removed-key', 'tab'],
      'customKeys': <Object?>[],
    });

    expect(layout.orderedIds, isNot(contains('removed-key')));
    expect(layout.hiddenIds, <String>{'tab'});
  });

  test('Merges new built-ins next to their canonical neighbors', () {
    // A saved order missing shiftTab (added later) keeps the user's custom
    // ordering and inserts shiftTab right after its canonical neighbor tab.
    final saved = <String>[
      'ctrlC',
      'escape',
      'tab',
      'enter',
      for (final key in builtInTerminalAccessoryKeys)
        if (!<String>{
          'ctrlC',
          'escape',
          'tab',
          'enter',
          'shiftTab',
        }.contains(key.id))
          key.id,
    ];

    final merged = mergeMissingBuiltInIds(saved);

    // shiftTab's nearest preceding canonical neighbor is enter.
    expect(merged.indexOf('shiftTab'), merged.indexOf('enter') + 1);
    expect(merged.first, 'ctrlC');
    expect(merged.toSet(), <String>{
      for (final key in builtInTerminalAccessoryKeys) key.id,
    });
  });

  test('Resolves custom keys through the shortcut builder', () {
    final layout = TerminalAccessoryLayout.defaults().copyWith(
      customKeys: <TerminalCustomKey>[
        const TerminalCustomKey(
          id: 'custom-1',
          key: 'arrowUp',
          modifiers: <TerminalShortcutModifier>{TerminalShortcutModifier.ctrl},
        ),
      ],
    );

    final resolved =
        layout.orderedKeys().where((key) => key.id == 'custom-1').single
            as TerminalAccessoryBytesKey;
    expect(resolved.label, 'Ctrl+↑');
    expect(resolved.bytes, '\x1b[1;5A'.codeUnits);
  });

  test('Defaults lead with the vertical arrows', () {
    expect(TerminalAccessoryLayout.defaults().orderedIds.take(2), <String>[
      'arrowUp',
      'arrowDown',
    ]);
  });

  test('A layout saved before paste existed gains it after arrowDown', () {
    // The order a user upgrading from the pinned-rail build has stored.
    const savedOrder = <String>[
      'escape',
      'tab',
      'enter',
      'shiftTab',
      'space',
      'backspace',
      'delete',
      'arrowUp',
      'arrowDown',
      'arrowLeft',
      'arrowRight',
      'ctrlC',
      'ctrlD',
      'ctrlL',
      'ctrlZ',
      'ctrlR',
      'ctrlA',
      'ctrlE',
      'ctrlW',
      'ctrlU',
    ];
    final layout = TerminalAccessoryLayout.fromJson(<String, Object?>{
      'version': 1,
      'orderedIds': savedOrder,
      'hiddenIds': <String>['ctrlU'],
      'customKeys': <Object?>[],
    });

    expect(
      layout.orderedIds.indexOf('paste'),
      layout.orderedIds.indexOf('arrowDown') + 1,
    );
    // Nothing the user chose is reshuffled by the upgrade.
    expect(layout.orderedIds.where((id) => id != 'paste').toList(), savedOrder);
    expect(layout.hiddenIds, <String>{'ctrlU'});
  });

  test('Paste resolves to an action key and custom keys to byte keys', () {
    final layout = TerminalAccessoryLayout.defaults().copyWith(
      customKeys: <TerminalCustomKey>[
        const TerminalCustomKey(
          id: 'custom-1',
          key: 'k',
          modifiers: <TerminalShortcutModifier>{TerminalShortcutModifier.ctrl},
        ),
      ],
    );
    final byId = <String, TerminalAccessoryKey>{
      for (final key in layout.orderedKeys()) key.id: key,
    };

    expect(byId['paste'], isA<TerminalAccessoryActionKey>());
    expect(byId['custom-1'], isA<TerminalAccessoryBytesKey>());
    expect(byId['arrowUp'], isA<TerminalAccessoryBytesKey>());
  });

  test('Visible keys exclude hidden ids', () {
    final layout = TerminalAccessoryLayout.defaults().copyWith(
      hiddenIds: <String>{'escape', 'ctrlU'},
    );

    final visibleIds = layout.visibleKeys().map((key) => key.id).toSet();
    expect(visibleIds, isNot(contains('escape')));
    expect(visibleIds, isNot(contains('ctrlU')));
    expect(visibleIds, contains('tab'));
  });
}
