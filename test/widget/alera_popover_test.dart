import 'package:alera/src/design_system/surfaces/alera_popover.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  AleraPopoverController? controller,
  bool toggleOnAnchorTap = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: .topCenter,
          child: Column(
            mainAxisSize: .min,
            children: <Widget>[
              const TextField(key: Key('before')),
              AleraPopover(
                controller: controller,
                toggleOnAnchorTap: toggleOnAnchorTap,
                width: 200,
                builder: (context, close) => Column(
                  mainAxisSize: .min,
                  children: <Widget>[
                    const Text('Popover Body'),
                    TextButton(onPressed: close, child: const Text('Done')),
                  ],
                ),
                child: const Text('Anchor'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('tapping a passive anchor toggles the popover', (tester) async {
    await _pump(tester);
    expect(find.text('Popover Body'), findsNothing);

    await tester.tap(find.text('Anchor'));
    await tester.pumpAndSettle();
    expect(find.text('Popover Body'), findsOneWidget);

    // The barrier covers the anchor, so a second tap closes it.
    await tester.tap(find.text('Anchor'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Popover Body'), findsNothing);
  });

  testWidgets('controller opens and closes it', (tester) async {
    final controller = AleraPopoverController();
    addTearDown(controller.dispose);
    await _pump(tester, controller: controller, toggleOnAnchorTap: false);

    controller.open();
    await tester.pumpAndSettle();
    expect(find.text('Popover Body'), findsOneWidget);

    controller.close();
    await tester.pumpAndSettle();
    expect(find.text('Popover Body'), findsNothing);
  });

  testWidgets('Escape closes it and returns focus to the previous owner', (
    tester,
  ) async {
    final controller = AleraPopoverController();
    addTearDown(controller.dispose);
    await _pump(tester, controller: controller);

    await tester.tap(find.byKey(const Key('before')));
    await tester.pump();
    final before = FocusManager.instance.primaryFocus;

    controller.open();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, isNot(before));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Popover Body'), findsNothing);
    expect(controller.isOpen, isFalse);
    expect(FocusManager.instance.primaryFocus, before);
  });

  testWidgets('tapping outside closes it', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Anchor'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(5, 590));
    await tester.pumpAndSettle();
    expect(find.text('Popover Body'), findsNothing);
  });

  testWidgets('the close callback dismisses it', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Anchor'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Popover Body'), findsNothing);
  });

  testWidgets('opens above an anchor near the bottom edge', (tester) async {
    final controller = AleraPopoverController()..open();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: .bottomCenter,
            child: AleraPopover(
              controller: controller,
              width: 200,
              builder: (context, close) =>
                  const SizedBox(height: 120, child: Text('Popover Body')),
              child: const Text('Anchor'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final body = tester.getTopLeft(find.text('Popover Body'));
    final anchor = tester.getTopLeft(find.text('Anchor'));
    expect(body.dy, lessThan(anchor.dy));
  });
}
