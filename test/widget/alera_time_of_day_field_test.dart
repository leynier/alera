import 'package:alera/src/design_system/forms/alera_time_of_day_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 240,
          child: Column(
            mainAxisSize: .min,
            children: <Widget>[
              child,
              const TextField(key: Key('other')),
            ],
          ),
        ),
      ),
    ),
  );
}

Finder get _timeInput => find.descendant(
  of: find.byType(AleraTimeOfDayField),
  matching: find.byType(TextField),
);

String _text(WidgetTester tester) =>
    tester.widget<TextField>(_timeInput).controller!.text;

void main() {
  testWidgets('shows the time zero-padded', (tester) async {
    await tester.pumpWidget(
      _wrap(AleraTimeOfDayField(hour: 9, minute: 5, onChanged: (_, _) {})),
    );
    expect(_text(tester), '09:05');
  });

  testWidgets('Enter commits a parsed time once and normalizes the text', (
    tester,
  ) async {
    final changes = <(int, int)>[];
    await tester.pumpWidget(
      _wrap(
        AleraTimeOfDayField(
          hour: 9,
          minute: 0,
          onChanged: (hour, minute) => changes.add((hour, minute)),
        ),
      ),
    );

    await tester.enterText(_timeInput, '6:30 pm');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(changes, <(int, int)>[(18, 30)]);
    expect(_text(tester), '18:30');
  });

  testWidgets('blur commits the typed time', (tester) async {
    final changes = <(int, int)>[];
    await tester.pumpWidget(
      _wrap(
        AleraTimeOfDayField(
          hour: 9,
          minute: 0,
          onChanged: (hour, minute) => changes.add((hour, minute)),
        ),
      ),
    );

    await tester.enterText(_timeInput, '12am');
    await tester.tap(find.byKey(const Key('other')));
    await tester.pumpAndSettle();

    expect(changes, <(int, int)>[(0, 0)]);
    expect(_text(tester), '00:00');
  });

  testWidgets('invalid input shows an error and keeps the last value', (
    tester,
  ) async {
    final changes = <(int, int)>[];
    await tester.pumpWidget(
      _wrap(
        AleraTimeOfDayField(
          hour: 9,
          minute: 0,
          onChanged: (hour, minute) => changes.add((hour, minute)),
        ),
      ),
    );

    await tester.enterText(_timeInput, '25:99');
    await tester.tap(find.byKey(const Key('other')));
    await tester.pumpAndSettle();

    expect(changes, isEmpty);
    expect(find.text(AleraTimeOfDayField.invalidMessage), findsOneWidget);

    await tester.enterText(_timeInput, '9:45');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(changes, <(int, int)>[(9, 45)]);
    expect(find.text(AleraTimeOfDayField.invalidMessage), findsNothing);
  });
}
