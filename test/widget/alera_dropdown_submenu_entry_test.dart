import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_submenu_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('submenu assigns the nested value to the parent menu', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        theme: aleraDarkTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await showMenu<String>(
                  context: context,
                  position: const RelativeRect.fromLTRB(0, 0, 0, 0),
                  items: const <PopupMenuEntry<String>>[
                    AleraDropdownSubmenuEntry<String>(
                      label: 'Set Section',
                      items: <PopupMenuEntry<String>>[
                        AleraDropdownEntry<String>(
                          value: 'work',
                          label: 'Work',
                        ),
                        AleraDropdownEntry<String>(
                          value: 'new',
                          label: 'New Section',
                        ),
                      ],
                    ),
                  ],
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set Section'));
    await tester.pumpAndSettle();
    expect(find.text('Work'), findsOneWidget);
    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    expect(selected, 'work');
  });
}
