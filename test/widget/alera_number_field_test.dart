import 'package:alera/src/design_system/forms/alera_number_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('invalid input resets to the current formatted value', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AleraNumberField(
            value: 12,
            min: 1,
            max: 48,
            step: 1,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'not-a-number');
    await tester.testTextInput.receiveAction(.done);
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '12',
    );
  });
}
