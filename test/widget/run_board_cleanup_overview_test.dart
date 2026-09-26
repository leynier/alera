import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/orchestration/presentation/run_board_detail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/run_board_fixtures.dart';

void main() {
  testWidgets('cleanup cause stays explicit and opens resource inspection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final attention in [false, true]) {
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: aleraDarkTheme,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: RunBoardDetail(
                snapshot: boardRunDetail(
                  cleanupAttention: attention,
                  cleanupApplying: !attention,
                ),
                onTask: (_) {},
                onBack: () {},
                onCleanup: () => opened = true,
                footer: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          attention
              ? 'Resource cleanup needs attention.'
              : 'Resource cleanup is in progress.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Manage Resources'));
      expect(opened, true);
      expect(tester.takeException(), isNull);
    }
  });
}
