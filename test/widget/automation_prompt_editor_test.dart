import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/automations/presentation/composer/automation_prompt_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<AutomationTemplateTextController> mount(WidgetTester tester) async {
    final controller = AutomationTemplateTextController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: AutomationPromptEditor(
              controller: controller,
              onChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    return controller;
  }

  Finder field() => find.descendant(
    of: find.byType(AutomationPromptEditor),
    matching: find.byType(TextField),
  );

  testWidgets('typing {{ offers variables and Tab inserts one', (tester) async {
    final controller = await mount(tester);
    await tester.enterText(field(), 'Check {{run.n');
    await tester.pumpAndSettle();
    expect(find.text('{{run.number}}'), findsOneWidget);
    expect(find.text('Tab or Enter inserts. Esc closes.'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(controller.text, 'Check {{run.number}}');
    expect(find.text('Tab or Enter inserts. Esc closes.'), findsNothing);
  });

  testWidgets('a chip inserts its variable at the caret', (tester) async {
    final controller = await mount(tester);
    await tester.enterText(field(), 'Review ');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Project Name'));
    await tester.pumpAndSettle();
    expect(controller.text, 'Review {{project.name}}');
  });

  testWidgets('an unknown variable is reported before saving', (tester) async {
    await mount(tester);
    await tester.enterText(field(), 'Check {{run.nmber}}');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('is not a variable Alera knows'),
      findsOneWidget,
    );
  });
}
