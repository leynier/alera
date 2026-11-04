import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/forms/alera_composer_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const List<AleraComposerMenuItem> _items = <AleraComposerMenuItem>[
  AleraComposerMenuItem(id: 'a', label: 'main.dart', detail: 'lib'),
  AleraComposerMenuItem(id: 'b', label: 'README.md'),
  AleraComposerMenuItem(
    id: 'c',
    label: '/plan',
    disabledReason: 'Plan mode is already on.',
  ),
];

Widget _host({
  List<AleraComposerMenuItem> items = _items,
  int activeIndex = 0,
  bool loading = false,
  ValueChanged<int>? onPick,
  ValueChanged<int>? onActiveChanged,
}) => MaterialApp(
  theme: buildAleraDarkTheme(),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 320,
        child: AleraComposerMenu(
          items: items,
          activeIndex: activeIndex,
          semanticsLabel: 'File Mentions',
          title: 'Files',
          loading: loading,
          emptyMessage: 'No matching files.',
          onPick: onPick ?? (_) {},
          onActiveChanged: onActiveChanged,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('the active row carries the rail and picks on tap', (
    tester,
  ) async {
    final picked = <int>[];
    await tester.pumpWidget(_host(activeIndex: 1, onPick: picked.add));

    expect(find.text('Files'), findsOneWidget);
    expect(find.text('lib'), findsOneWidget);
    final rail = find.byKey(const ValueKey<String>('alera-active-rail'));
    expect(rail, findsOneWidget);
    expect(
      find.ancestor(
        of: rail,
        matching: find.byKey(const ValueKey<String>('alera-composer-menu-b')),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('main.dart'));
    expect(picked, <int>[0]);
  });

  testWidgets('a disabled row shows its reason and cannot be picked', (
    tester,
  ) async {
    final picked = <int>[];
    await tester.pumpWidget(_host(onPick: picked.add));

    expect(find.text('Plan mode is already on.'), findsOneWidget);
    await tester.tap(find.text('/plan'));
    expect(picked, isEmpty);
  });

  testWidgets('hovering a row makes it active', (tester) async {
    final active = <int>[];
    await tester.pumpWidget(_host(onActiveChanged: active.add));

    final mouse = await tester.createGesture(kind: .mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('README.md')));
    await tester.pump();
    expect(active, <int>[1]);
  });

  testWidgets('an empty or loading list says so', (tester) async {
    await tester.pumpWidget(_host(items: const <AleraComposerMenuItem>[]));
    expect(find.text('No matching files.'), findsOneWidget);

    await tester.pumpWidget(
      _host(items: const <AleraComposerMenuItem>[], loading: true),
    );
    expect(find.text('Searching…'), findsOneWidget);
  });

  testWidgets('rows expose their state to assistive technology', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host());

    expect(
      tester.getSemantics(
        find.byKey(const ValueKey<String>('alera-composer-menu-a')),
      ),
      matchesSemantics(
        label: 'main.dart',
        value: '1 of 3',
        hint: 'lib',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey<String>('alera-composer-menu-c')),
      ),
      matchesSemantics(
        label: '/plan',
        value: '3 of 3',
        hint: 'Plan mode is already on.',
        isButton: true,
        hasSelectedState: true,
        hasEnabledState: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('the active row is announced when it changes', (tester) async {
    final announcements = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
      SystemChannels.accessibility,
      (message) async {
        final data = (message! as Map<Object?, Object?>)['data'];
        if (data case {'message': final String text}) announcements.add(text);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(
            SystemChannels.accessibility,
            null,
          ),
    );

    await tester.pumpWidget(_host());
    await tester.pump();
    await tester.pumpWidget(_host(activeIndex: 1));
    await tester.pump();
    await tester.pumpWidget(_host(activeIndex: 1));
    await tester.pump();

    expect(announcements, <String>[
      'main.dart, lib, 1 of 3',
      'README.md, 2 of 3',
    ]);
  });

  testWidgets('keys map to menu moves and wrap at both ends', (tester) async {
    final results = <AleraComposerMenuKey?>[];
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      Focus(
        focusNode: node,
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent) {
            results.add(AleraComposerMenu.keyFor(event));
          }
          return KeyEventResult.handled;
        },
        child: const SizedBox(),
      ),
    );
    await tester.pump();

    for (final key in <LogicalKeyboardKey>[
      .arrowUp,
      .arrowDown,
      .enter,
      .tab,
      .escape,
      .keyA,
    ]) {
      await tester.sendKeyEvent(key);
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(results, <AleraComposerMenuKey?>[
      .previous,
      .next,
      .pick,
      .pick,
      .dismiss,
      null,
      null,
      null,
    ]);
    expect(AleraComposerMenu.step(0, 3, -1), 2);
    expect(AleraComposerMenu.step(2, 3, 1), 0);
    expect(AleraComposerMenu.step(0, 0, 1), 0);
  });
}
