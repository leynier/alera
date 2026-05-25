import 'package:alera/src/design_system/forms/alera_search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpField(
    WidgetTester tester, {
    TextEditingController? controller,
    FocusNode? focusNode,
    ValueChanged<String>? onChanged,
    Duration? debounce,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: AleraSearchField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              debounce: debounce,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('clear button resets the controller and emits an empty search', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'query');
    addTearDown(controller.dispose);
    final values = <String>[];

    await pumpField(tester, controller: controller, onChanged: values.add);

    expect(find.byTooltip('Clear'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();

    expect(controller.text, isEmpty);
    expect(values, <String>['']);
  });

  testWidgets('debounce delays search change notifications', (tester) async {
    final values = <String>[];

    await pumpField(
      tester,
      onChanged: values.add,
      debounce: const Duration(milliseconds: 200),
    );

    await tester.enterText(find.byType(TextField), 'alera');
    await tester.pump(const Duration(milliseconds: 100));
    expect(values, isEmpty);

    await tester.pump(const Duration(milliseconds: 120));
    expect(values, <String>['alera']);
  });

  testWidgets('escape clears text first and then unfocuses when already empty', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'filter');
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await pumpField(
      tester,
      controller: controller,
      focusNode: focusNode,
      onChanged: (_) {},
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);
    expect(focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(focusNode.hasFocus, isFalse);
  });
}
