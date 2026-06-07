import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/feedback/alera_toast_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows and dismisses a success toast after its duration', (
    tester,
  ) async {
    await _pumpToastHarness(
      tester,
      onPressed: (context) {
        AleraToast.show(
          context,
          message: 'Project added',
          tone: AleraToastTone.success,
          duration: const Duration(milliseconds: 20),
        );
      },
    );

    await tester.tap(find.text('Show'));
    await tester.pump();

    expect(find.text('Project added'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(AleraTokens.durationMid);

    expect(find.text('Project added'), findsNothing);
  });

  testWidgets('positions toasts at the bottom right of the host', (
    tester,
  ) async {
    await _pumpToastHarness(
      tester,
      onPressed: (context) {
        AleraToast.show(
          context,
          message: 'Saved',
          duration: const Duration(milliseconds: 20),
        );
      },
    );

    await tester.tap(find.text('Show'));
    await tester.pump();

    final toastBottomLeft = tester.getBottomLeft(find.text('Saved'));
    final toastTopRight = tester.getTopRight(find.text('Saved'));
    final screenSize = tester.view.physicalSize / tester.view.devicePixelRatio;

    expect(toastBottomLeft.dy, greaterThan(screenSize.height * 0.75));
    expect(toastTopRight.dx, greaterThan(screenSize.width * 0.75));
  });

  testWidgets(
    'queues toasts beyond the visible limit and drains them in order',
    (tester) async {
      await _pumpToastHarness(
        tester,
        onPressed: (context) {
          for (var index = 1; index <= 4; index += 1) {
            AleraToast.show(
              context,
              message: 'Toast $index',
              duration: const Duration(milliseconds: 20),
            );
          }
        },
      );

      await tester.tap(find.text('Show'));
      await tester.pump();

      expect(find.text('Toast 1'), findsOneWidget);
      expect(find.text('Toast 2'), findsOneWidget);
      expect(find.text('Toast 3'), findsOneWidget);
      expect(find.text('Toast 4'), findsNothing);

      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(AleraTokens.durationMid);

      expect(find.text('Toast 4'), findsOneWidget);
    },
  );
}

Future<void> _pumpToastHarness(
  WidgetTester tester, {
  required void Function(BuildContext context) onPressed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Stack(
          children: <Widget>[
            Center(
              child: Builder(
                builder: (context) {
                  return FilledButton(
                    onPressed: () => onPressed(context),
                    child: const Text('Show'),
                  );
                },
              ),
            ),
            const AleraToastHost(),
          ],
        ),
      ),
    ),
  );
}
