import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/surfaces/hover_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hover container animates between base and hover colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: HoverContainer(
            baseColor: Colors.red,
            hoverColor: Colors.blue,
            child: SizedBox(width: 80, height: 40),
          ),
        ),
      ),
    );

    BoxDecoration decorationOf() =>
        tester
                .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                .decoration!
            as BoxDecoration;

    expect(decorationOf().color, Colors.red);

    final mouse = await tester.createGesture(kind: .mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: .zero);
    await tester.pump();

    await mouse.moveTo(tester.getCenter(find.byType(HoverContainer)));
    await tester.pumpAndSettle(AleraTokens.durationFast);
    expect(decorationOf().color, Colors.blue);

    await mouse.moveTo(const Offset(500, 500));
    await tester.pumpAndSettle(AleraTokens.durationFast);
    expect(decorationOf().color, Colors.red);
  });

  testWidgets('tappable hover container answers on empty space', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 40,
              child: HoverContainer(
                onTap: () => taps++,
                child: const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Label'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final box = tester.getRect(find.byType(HoverContainer));
    await tester.tapAt(Offset(box.right - 4, box.center.dy));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });
}
