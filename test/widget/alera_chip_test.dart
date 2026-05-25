import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/chips/alera_chip.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('removable chips update their surface color on hover', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AleraChip(label: 'Orca', onRemove: () {}),
          ),
        ),
      ),
    );

    BoxDecoration decorationOf() =>
        tester
                .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                .decoration!
            as BoxDecoration;

    expect(decorationOf().color, AleraTokens.accentSubtle);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await tester.pump();

    await mouse.moveTo(tester.getCenter(find.text('Orca')));
    await tester.pumpAndSettle(AleraTokens.durationFast);
    expect(decorationOf().color, AleraTokens.surfaceElevated);

    await mouse.moveTo(const Offset(1, 1));
    await tester.pumpAndSettle(AleraTokens.durationFast);
    expect(decorationOf().color, AleraTokens.accentSubtle);
  });
}
