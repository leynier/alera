import 'dart:async';

import 'package:alera/src/features/settings/presentation/rows/settings_rows.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(SettingsButtonRow row) => MaterialApp(home: Scaffold(body: row));

  OutlinedButton button(WidgetTester tester) =>
      tester.widget<OutlinedButton>(find.byType(OutlinedButton));

  testWidgets('disables the button when no action is supplied', (tester) async {
    await tester.pumpWidget(
      host(
        const SettingsButtonRow(
          title: 'Reload Shell Environment',
          description: 'Re-read the login shell PATH.',
          buttonLabel: 'Reload',
        ),
      ),
    );

    expect(button(tester).onPressed, isNull);
  });

  testWidgets('shows a spinner, disables, and ignores taps while running', (
    tester,
  ) async {
    final completer = Completer<void>();
    var calls = 0;

    await tester.pumpWidget(
      host(
        SettingsButtonRow(
          title: 'Reload Shell Environment',
          description: 'Re-read the login shell PATH.',
          buttonLabel: 'Reload',
          onPressed: () {
            calls++;
            return completer.future;
          },
        ),
      ),
    );

    expect(find.text('Reload'), findsOneWidget);

    await tester.tap(find.byType(OutlinedButton));
    await tester.pump();

    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(button(tester).onPressed, isNull);

    // A second tap while the action is in flight must not start it again.
    await tester.tap(find.byType(OutlinedButton), warnIfMissed: false);
    await tester.pump();
    expect(calls, 1);

    completer.complete();
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Reload'), findsOneWidget);
    expect(button(tester).onPressed, isNotNull);
  });
}
