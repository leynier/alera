import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/workbench/presentation/welcome_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final width in [300.0, 312.0, 320.0, 327.0, 328.0, 400.0]) {
    testWidgets('Home menu fits a $width pixel window', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 500);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAleraDarkTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.centerRight,
              child: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    selected = await showHomeComposerMenu(
                      context: context,
                      choices: const [
                        HomeComposerMenuChoice(
                          value: 'checkout',
                          label: 'Current Checkout',
                        ),
                        HomeComposerMenuChoice(
                          value: 'worktree',
                          label: 'New Worktree',
                        ),
                      ],
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final menu = find
          .ancestor(
            of: find.widgetWithText(TextField, 'Search'),
            matching: find.byType(Material),
          )
          .first;
      final rect = tester.getRect(menu);
      expect(rect.left, greaterThanOrEqualTo(AleraTokens.space8));
      expect(rect.right, lessThanOrEqualTo(width - AleraTokens.space8));
      await tester.tap(find.text('New Worktree'));
      await tester.pumpAndSettle();
      expect(selected, 'worktree');
    });
  }
}
