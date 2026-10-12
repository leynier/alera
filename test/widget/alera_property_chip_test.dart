import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/chips/alera_property_chip.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

Border? _chipBorder(WidgetTester tester) {
  final container = tester.widget<Container>(
    find.ancestor(of: find.byType(Row), matching: find.byType(Container)).first,
  );
  return (container.decoration as BoxDecoration?)?.border as Border?;
}

void main() {
  testWidgets('renders the label, value and From Context badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        AleraPropertyChip(
          icon: AleraIcons.folder,
          label: 'In',
          value: 'alera / main',
          fromContext: true,
          onTap: () {},
        ),
      ),
    );

    expect(find.text('In'), findsOneWidget);
    expect(find.text('alera / main'), findsOneWidget);
    expect(
      find.widgetWithText(AleraBadge, AleraPropertyChip.fromContextLabel),
      findsOneWidget,
    );
    expect(find.byIcon(AleraIcons.chevronDown), findsOneWidget);
    expect(_chipBorder(tester)?.top.color, AleraTokens.border);
  });

  testWidgets('error state draws the error border', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AleraPropertyChip(
          value: 'Choose Destination',
          hasError: true,
          onTap: () {},
        ),
      ),
    );

    expect(_chipBorder(tester)?.top.color, AleraTokens.error);
    expect(find.byType(AleraBadge), findsNothing);
  });

  testWidgets('Tab focuses the chip and Enter or Space activates it', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(AleraPropertyChip(value: 'Opus', onTap: () => taps++)),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(taps, 2);
  });

  testWidgets('clear button replaces the chevron and reports a clear', (
    tester,
  ) async {
    var cleared = 0;
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        AleraPropertyChip(
          value: 'Same Conversation',
          onTap: () => taps++,
          onClear: () => cleared++,
        ),
      ),
    );

    expect(find.byIcon(AleraIcons.chevronDown), findsNothing);
    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();
    expect(cleared, 1);
    expect(taps, 0);
  });

  testWidgets('without onTap the chip is disabled', (tester) async {
    await tester.pumpWidget(_wrap(const AleraPropertyChip(value: 'Locked')));

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final text = tester.widget<Text>(find.text('Locked'));
    expect(text.style?.color, AleraTokens.foregroundFaint);
  });
}
