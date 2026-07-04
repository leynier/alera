import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 240, child: child)),
    ),
  );
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
}
