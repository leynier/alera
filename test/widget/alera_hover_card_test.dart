import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/surfaces/alera_hover_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap({
  AleraHoverCardController? controller,
  bool pinOnTap = true,
  ValueChanged<bool>? onVisibilityChanged,
  VoidCallback? onTriggerPressed,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: AleraHoverCard(
          controller: controller,
          pinOnTap: pinOnTap,
          semanticsLabel: 'Trigger',
          onVisibilityChanged: onVisibilityChanged,
          card: const Material(child: Text('Card Body')),
          child: Material(
            child: InkWell(
              onTap: onTriggerPressed,
              child: const SizedBox(
                width: 120,
                height: 30,
                child: Text('Chip'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<TestGesture> _mouse(WidgetTester tester) async {
  final mouse = await tester.createGesture(kind: .mouse);
  addTearDown(mouse.removePointer);
  await mouse.addPointer(location: .zero);
  await tester.pump();
  return mouse;
}

/// Long enough to clear the open delay, the close grace period and the fade.
const Duration _settle = Duration(milliseconds: 600);

void main() {
  testWidgets('hovering the trigger opens the card and leaving closes it', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap());
    expect(find.text('Card Body'), findsNothing);

    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(find.text('Chip')));
    await tester.pumpAndSettle(_settle);
    expect(find.text('Card Body'), findsOneWidget);

    await mouse.moveTo(const Offset(20, 20));
    await tester.pumpAndSettle(_settle);
    expect(find.text('Card Body'), findsNothing);
  });

  testWidgets('a controller pins the card for a trigger that owns its taps', (
    tester,
  ) async {
    final controller = AleraHoverCardController();
    await tester.pumpWidget(
      _wrap(
        controller: controller,
        pinOnTap: false,
        onTriggerPressed: controller.togglePin,
      ),
    );

    // The trigger's own InkWell handles the tap; the card never sees it.
    await tester.tap(find.text('Chip'));
    await tester.pumpAndSettle(_settle);
    expect(find.text('Card Body'), findsOneWidget);

    // A pinned card outlives the pointer, which never entered it here.
    final mouse = await _mouse(tester);
    await mouse.moveTo(const Offset(20, 20));
    await tester.pumpAndSettle(_settle);
    expect(find.text('Card Body'), findsOneWidget);

    await tester.tap(find.text('Chip'));
    await tester.pumpAndSettle(_settle);
    expect(find.text('Card Body'), findsNothing);
  });

  testWidgets('dismiss closes a pinned card', (tester) async {
    final controller = AleraHoverCardController();
    await tester.pumpWidget(
      _wrap(
        controller: controller,
        pinOnTap: false,
        onTriggerPressed: controller.togglePin,
      ),
    );

    await tester.tap(find.text('Chip'));
    await tester.pumpAndSettle(_settle);
    expect(find.text('Card Body'), findsOneWidget);

    controller.dismiss();
    await tester.pumpAndSettle(_settle);
    expect(find.text('Card Body'), findsNothing);
  });

  testWidgets('interacting with the card pins a card opened by hover', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap());

    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(find.text('Chip')));
    await tester.pumpAndSettle(_settle);
    expect(find.text('Card Body'), findsOneWidget);

    // Standing in for an action inside the card that opens a modal dialog: the
    // pointer leaves right after, and the card has to survive it.
    await tester.tap(find.text('Card Body'));
    await mouse.moveTo(const Offset(20, 20));
    await tester.pumpAndSettle(_settle);

    expect(find.text('Card Body'), findsOneWidget);
  });

  testWidgets('visibility is reported once per edge', (tester) async {
    final edges = <bool>[];
    await tester.pumpWidget(_wrap(onVisibilityChanged: edges.add));

    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(find.text('Chip')));
    await tester.pumpAndSettle(_settle);
    expect(edges, <bool>[true]);

    // Moving within the trigger reschedules without crossing an edge.
    await mouse.moveTo(
      tester.getCenter(find.text('Chip')) + const Offset(4, 0),
    );
    await tester.pumpAndSettle(AleraTokens.durationFast);
    expect(edges, <bool>[true]);

    await mouse.moveTo(const Offset(20, 20));
    await tester.pumpAndSettle(_settle);
    expect(edges, <bool>[true, false]);
  });

  testWidgets('an unmounted card reports that it is gone', (tester) async {
    final edges = <bool>[];
    await tester.pumpWidget(_wrap(onVisibilityChanged: edges.add));

    final mouse = await _mouse(tester);
    await mouse.moveTo(tester.getCenter(find.text('Chip')));
    await tester.pumpAndSettle(_settle);
    expect(edges, <bool>[true]);

    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pumpAndSettle();

    expect(edges, <bool>[true, false]);
  });
}
