import 'package:alera/src/design_system/forms/alera_date_time_field.dart';
import 'package:alera/src/design_system/forms/alera_time_of_day_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 380, child: child)),
    ),
  );
}

Finder get _timeInput => find.descendant(
  of: find.byType(AleraTimeOfDayField),
  matching: find.byType(TextField),
);

void main() {
  testWidgets('editing the time keeps the date', (tester) async {
    final changes = <DateTime?>[];
    await tester.pumpWidget(
      _wrap(
        AleraDateTimeField(
          value: DateTime(2026, 10, 13, 9),
          onChanged: changes.add,
        ),
      ),
    );

    await tester.enterText(_timeInput, '14:15');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(changes, <DateTime?>[DateTime(2026, 10, 13, 14, 15)]);
  });

  testWidgets('picking a date keeps the time typed before it', (tester) async {
    final changes = <DateTime?>[];
    await tester.pumpWidget(
      _wrap(
        AleraDateTimeField(
          value: null,
          firstDate: DateTime(2026, 10),
          lastDate: DateTime(2026, 10, 31),
          onChanged: changes.add,
        ),
      ),
    );

    await tester.enterText(_timeInput, '7:45 am');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(changes, isEmpty);

    await tester.tap(find.text('Choose Date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(changes, <DateTime?>[DateTime(2026, 10, 20, 7, 45)]);
  });

  testWidgets('Clear resets the value when clearable', (tester) async {
    final changes = <DateTime?>[];
    await tester.pumpWidget(
      _wrap(
        AleraDateTimeField(
          value: DateTime(2026, 10, 13, 9),
          clearable: true,
          onChanged: changes.add,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();
    expect(changes, <DateTime?>[null]);
  });
}
