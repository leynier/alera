import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/surfaces/alera_active_rail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpRow(WidgetTester tester, {required bool active}) {
  return tester.pumpWidget(
    Directionality(
      textDirection: .ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 200,
          child: AleraActiveRail(
            active: active,
            child: const SizedBox(key: Key('row'), height: 32),
          ),
        ),
      ),
    ),
  );
}

void main() {
  const rail = Key('alera-active-rail');

  testWidgets('an active row draws an inset accent rail at its leading edge', (
    tester,
  ) async {
    await _pumpRow(tester, active: true);

    final rect = tester.getRect(find.byKey(rail));
    expect(rect.left, 0);
    expect(rect.width, AleraTokens.activeRailWidth);
    expect(rect.top, AleraTokens.space6);
    expect(rect.bottom, 32 - AleraTokens.space6);
    final decoration =
        tester.widget<DecoratedBox>(find.byKey(rail)).decoration
            as BoxDecoration;
    expect(decoration.color, AleraTokens.accent);
  });

  testWidgets('selecting a row does not change its size', (tester) async {
    await _pumpRow(tester, active: false);
    expect(find.byKey(rail), findsNothing);
    final idle = tester.getSize(find.byKey(const Key('row')));

    await _pumpRow(tester, active: true);
    expect(find.byKey(rail), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('row'))), idle);
  });

  testWidgets('the rail ignores pointer events', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: .ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 200,
            child: AleraActiveRail(
              active: true,
              child: GestureDetector(
                behavior: .opaque,
                onTap: () => taps++,
                child: const SizedBox(height: 32),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tapAt(tester.getCenter(find.byKey(rail)));
    expect(taps, 1);
  });
}
