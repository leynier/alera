import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('tapping toggles the value', (tester) async {
    bool? next;
    await tester.pumpWidget(
      _wrap(
        AleraCheckbox(
          value: false,
          label: 'Overwrite',
          onChanged: (value) => next = value,
        ),
      ),
    );

    await tester.tap(find.text('Overwrite'));
    expect(next, isTrue);
  });

  testWidgets('disabled checkbox ignores taps', (tester) async {
    bool? next;
    await tester.pumpWidget(
      _wrap(
        AleraCheckbox(
          value: true,
          label: 'Overwrite',
          enabled: false,
          onChanged: (value) => next = value,
        ),
      ),
    );

    await tester.tap(find.text('Overwrite'));
    expect(next, isNull);
  });
}
