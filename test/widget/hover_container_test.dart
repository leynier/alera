import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/surfaces/hover_container.dart';
import 'package:flutter/gestures.dart';
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

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await tester.pump();

    await mouse.moveTo(tester.getCenter(find.byType(HoverContainer)));
    await tester.pumpAndSettle(AleraTokens.durationFast);
    expect(decorationOf().color, Colors.blue);

    await mouse.moveTo(const Offset(500, 500));
    await tester.pumpAndSettle(AleraTokens.durationFast);
    expect(decorationOf().color, Colors.red);
  });
}
