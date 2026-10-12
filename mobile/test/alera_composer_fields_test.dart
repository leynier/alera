import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/design_system/forms/alera_duration_field.dart';
import 'package:alera_mobile/src/design_system/forms/alera_time_of_day_field.dart';
import 'package:alera_mobile/src/design_system/layout/alera_collapsible_section.dart';
import 'package:alera_mobile/src/design_system/layout/alera_key_value_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  theme: buildAleraMobileDarkTheme(),
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(16), child: child),
  ),
);

void main() {
  test('durations display in the largest unit that divides them', () {
    expect(aleraDurationDisplayUnit(900), AleraDurationUnit.minutes);
    expect(aleraDurationDisplayUnit(7200), AleraDurationUnit.hours);
    expect(aleraDurationDisplayUnit(90), AleraDurationUnit.seconds);
    expect(aleraDurationLabel(86400), '1 day');
    expect(aleraDurationLabel(120), '2 minutes');
  });

  testWidgets('the duration field reports seconds and never clamps', (
    tester,
  ) async {
    final reported = <int>[];
    await tester.pumpWidget(
      _host(
        AleraDurationField(
          labelText: 'Inactivity Timeout',
          seconds: 900,
          errorText: 'Use at most 1 day.',
          onChanged: reported.add,
        ),
      ),
    );
    expect(find.text('15'), findsOneWidget);
    expect(find.text('Minutes'), findsOneWidget);
    expect(find.text('Use at most 1 day.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '2');
    expect(reported, <int>[120]);
    await tester.enterText(find.byType(TextField), '.');
    await tester.pump();
    expect(find.text(AleraDurationField.invalidMessage), findsOneWidget);
    expect(reported, <int>[120]);
  });

  testWidgets('the time field shows a padded time', (tester) async {
    await tester.pumpWidget(
      _host(AleraTimeOfDayField(hour: 9, minute: 5, onChanged: (_, _) {})),
    );
    expect(find.text('09:05'), findsOneWidget);
    expect(formatAleraTimeOfDay(18, 30), '18:30');
  });

  testWidgets('a collapsible section toggles its child', (tester) async {
    await tester.pumpWidget(
      _host(
        const AleraCollapsibleSection(
          title: 'Description',
          child: Text('Body'),
        ),
      ),
    );
    expect(find.text('Body'), findsNothing);
    await tester.tap(find.text('Description'));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsOneWidget);
    await tester.tap(find.text('Description'));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsNothing);
  });

  testWidgets('a controlled collapsible section only reports', (tester) async {
    final requested = <bool>[];
    await tester.pumpWidget(
      _host(
        AleraCollapsibleSection(
          title: 'Options',
          expanded: false,
          onExpandedChanged: requested.add,
          child: const Text('Body'),
        ),
      ),
    );
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    expect(requested, <bool>[true]);
    expect(find.text('Body'), findsNothing);
  });

  testWidgets('a key value row shows its label and value', (tester) async {
    await tester.pumpWidget(
      _host(const AleraKeyValueRow(label: 'Schedule', value: 'Daily')),
    );
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Daily'), findsOneWidget);
  });
}
