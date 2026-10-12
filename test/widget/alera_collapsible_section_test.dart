import 'package:alera/src/design_system/layout/alera_collapsible_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SizedBox(width: 400, child: child)),
  );
}

void main() {
  testWidgets('uncontrolled section toggles its body', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AleraCollapsibleSection(
          title: 'Options',
          description: 'Reliability and notifications.',
          trailing: Text('2'),
          child: Text('Body'),
        ),
      ),
    );
    expect(find.text('Body'), findsNothing);
    expect(find.text('Reliability and notifications.'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsOneWidget);

    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsNothing);
  });

  testWidgets('initiallyExpanded starts open', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const AleraCollapsibleSection(
          title: 'Options',
          initiallyExpanded: true,
          child: Text('Body'),
        ),
      ),
    );
    expect(find.text('Body'), findsOneWidget);
  });

  testWidgets('controlled section only follows its expanded value', (
    tester,
  ) async {
    final requests = <bool>[];
    Widget build({required bool expanded}) => _wrap(
      AleraCollapsibleSection(
        title: 'Options',
        expanded: expanded,
        onExpandedChanged: requests.add,
        child: const Text('Body'),
      ),
    );

    await tester.pumpWidget(build(expanded: false));
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    expect(requests, <bool>[true]);
    expect(find.text('Body'), findsNothing);

    await tester.pumpWidget(build(expanded: true));
    await tester.pumpAndSettle();
    expect(find.text('Body'), findsOneWidget);

    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    expect(requests, <bool>[true, false]);
    expect(find.text('Body'), findsOneWidget);
  });
}
