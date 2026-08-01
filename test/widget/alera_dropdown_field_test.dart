import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/menus/alera_menu_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 240, child: child)),
    ),
  );
}

Widget _filterableField({
  required String? value,
  required void Function(String?) onChanged,
}) {
  return _wrap(
    AleraDropdownField<String?>(
      value: value,
      filterable: true,
      filterHintText: 'Search Workspaces',
      entries: const <AleraDropdownFieldEntry<String?>>[
        AleraDropdownFieldEntry<String?>(value: null, label: 'No Parent'),
        AleraDropdownFieldEntry<String?>(
          value: 'alpha',
          label: 'alera / alpha',
        ),
        AleraDropdownFieldEntry<String?>(value: 'beta', label: 'alera / beta'),
        AleraDropdownFieldEntry<String?>(
          value: 'blocked',
          label: 'alera / blocked',
          enabled: false,
        ),
      ],
      onChanged: onChanged,
    ),
  );
}

Future<void> _openFilterable(WidgetTester tester) async {
  await tester.tap(find.byType(AleraDropdownField<String?>));
  await tester.pump();
}

const List<AleraDropdownFieldEntry<String>> _entries =
    <AleraDropdownFieldEntry<String>>[
      AleraDropdownFieldEntry<String>(value: 'agent', label: 'SSH Agent'),
      AleraDropdownFieldEntry<String>(value: 'key', label: 'Private Key'),
      AleraDropdownFieldEntry<String>(
        value: 'password',
        label: 'Password',
        enabled: false,
      ),
    ];

void main() {
  testWidgets('shows the selected label and reports a picked value', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      _wrap(
        AleraDropdownField<String>(
          value: 'agent',
          entries: _entries,
          onChanged: (value) => picked = value,
        ),
      ),
    );

    expect(find.text('SSH Agent'), findsOneWidget);

    await tester.tap(find.text('SSH Agent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Private Key'));
    await tester.pumpAndSettle();

    expect(picked, 'key');
  });

  testWidgets('disabled entries cannot be picked', (tester) async {
    String? picked;
    await tester.pumpWidget(
      _wrap(
        AleraDropdownField<String>(
          value: 'agent',
          entries: _entries,
          onChanged: (value) => picked = value,
        ),
      ),
    );

    await tester.tap(find.text('SSH Agent'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Password'));
    await tester.pumpAndSettle();

    expect(picked, isNull);
    // The menu stays open because the disabled entry did not pop it.
    expect(find.text('Private Key'), findsOneWidget);
  });

  testWidgets('shows the hint when no value is selected', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AleraDropdownField<String>(
          value: null,
          hintText: 'Select An Option',
          entries: _entries,
          onChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Select An Option'), findsOneWidget);
  });

  testWidgets('shows the label above the field when provided', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AleraDropdownField<String>(
          value: 'agent',
          labelText: 'Auth Method',
          entries: _entries,
          onChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Auth Method'), findsOneWidget);
    expect(find.text('SSH Agent'), findsOneWidget);
  });

  testWidgets('a null-valued entry can be picked', (tester) async {
    String? picked = 'unset';
    await tester.pumpWidget(
      _wrap(
        AleraDropdownField<String?>(
          value: 'child',
          entries: const <AleraDropdownFieldEntry<String?>>[
            AleraDropdownFieldEntry<String?>(value: null, label: 'No Parent'),
            AleraDropdownFieldEntry<String?>(value: 'child', label: 'Child'),
          ],
          onChanged: (value) => picked = value,
        ),
      ),
    );

    await tester.tap(find.text('Child'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No Parent'));
    await tester.pumpAndSettle();

    expect(picked, isNull);
  });

  testWidgets('disabled field does not open the menu', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AleraDropdownField<String>(
          value: 'agent',
          enabled: false,
          entries: _entries,
          onChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.text('SSH Agent'));
    await tester.pumpAndSettle();

    expect(find.text('Private Key'), findsNothing);
  });

  testWidgets('filterable field narrows the options while typing', (
    tester,
  ) async {
    await tester.pumpWidget(
      _filterableField(value: 'alpha', onChanged: (_) {}),
    );

    await _openFilterable(tester);
    expect(find.byType(AleraMenuItem), findsNWidgets(4));

    await tester.enterText(find.byType(TextField), 'beta');
    await tester.pump();

    expect(find.byType(AleraMenuItem), findsOneWidget);
    expect(find.text('alera / beta'), findsOneWidget);
    // The trigger keeps showing the current selection.
    expect(find.text('alera / alpha'), findsOneWidget);
  });

  testWidgets('filter orders starts-with matches before contains matches', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AleraDropdownField<String>(
          value: null,
          filterable: true,
          entries: const <AleraDropdownFieldEntry<String>>[
            AleraDropdownFieldEntry<String>(
              value: 'private-key',
              label: 'Private Key',
            ),
            AleraDropdownFieldEntry<String>(
              value: 'keyboard',
              label: 'Keyboard',
            ),
          ],
          onChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.byType(AleraDropdownField<String>));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'key');
    await tester.pump();

    final keyboard = tester.getTopLeft(find.text('Keyboard'));
    final privateKey = tester.getTopLeft(find.text('Private Key'));
    expect(keyboard.dy, lessThan(privateKey.dy));
  });

  testWidgets('tapping a filtered option selects it and closes the popover', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      _filterableField(value: 'alpha', onChanged: (value) => picked = value),
    );

    await _openFilterable(tester);
    await tester.tap(find.text('alera / beta'));
    await tester.pump();

    expect(picked, 'beta');
    expect(find.byType(AleraMenuItem), findsNothing);
  });

  testWidgets('the null-valued entry can be picked in filterable mode', (
    tester,
  ) async {
    String? picked = 'unset';
    await tester.pumpWidget(
      _filterableField(value: 'alpha', onChanged: (value) => picked = value),
    );

    await _openFilterable(tester);
    await tester.tap(find.text('No Parent'));
    await tester.pump();

    expect(picked, isNull);
  });

  testWidgets('keyboard navigation skips disabled entries and selects', (
    tester,
  ) async {
    String? picked = 'unset';
    await tester.pumpWidget(
      _filterableField(value: 'alpha', onChanged: (value) => picked = value),
    );

    await _openFilterable(tester);
    // Highlight starts on the selected entry ('alpha'); two downs move past
    // 'beta' and wrap around the disabled 'blocked' onto 'No Parent'.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(picked, isNull);
    expect(find.byType(AleraMenuItem), findsNothing);
  });

  testWidgets('escape dismisses the filterable popover', (tester) async {
    await tester.pumpWidget(
      _filterableField(value: 'alpha', onChanged: (_) {}),
    );

    await _openFilterable(tester);
    expect(find.byType(AleraMenuItem), findsNWidgets(4));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.byType(AleraMenuItem), findsNothing);
  });

  testWidgets('shows an empty state when nothing matches', (tester) async {
    await tester.pumpWidget(
      _filterableField(value: 'alpha', onChanged: (_) {}),
    );

    await _openFilterable(tester);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();

    expect(find.text('No matching options'), findsOneWidget);
    expect(find.byType(AleraMenuItem), findsNothing);
  });

  testWidgets('tapping outside dismisses the filterable popover', (
    tester,
  ) async {
    await tester.pumpWidget(
      _filterableField(value: 'alpha', onChanged: (_) {}),
    );

    await _openFilterable(tester);
    expect(find.byType(AleraMenuItem), findsNWidgets(4));

    await tester.tapAt(const Offset(10, 10));
    await tester.pump();

    expect(find.byType(AleraMenuItem), findsNothing);
  });
}
