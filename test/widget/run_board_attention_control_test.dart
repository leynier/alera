import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/orchestration/application/run_board_navigation.dart';
import 'package:alera/src/features/orchestration/domain/run_board_snapshot.dart';
import 'package:alera/src/features/orchestration/infra/runtime_run_board_repository.dart';
import 'package:alera/src/features/orchestration/presentation/run_board_attention_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/run_board_fixtures.dart';
import '../support/run_board_widget_harness.dart';

void main() {
  testWidgets(
    'Attention counter opens the global board and releases its watcher',
    (tester) async {
      final repository = BoardTestRepository();
      final container = boardContainer(repository);
      addTearDown(container.dispose);
      addTearDown(repository.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAleraDarkTheme(),
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(2)),
                child: const Align(
                  alignment: Alignment.bottomLeft,
                  child: SizedBox(
                    height: AleraTokens.statusBarHeight,
                    child: RunBoardAttentionControl(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Open Run Board · 1 Run Needs Attention'),
        findsOneWidget,
      );
      expect(repository.queries.single.limit, 1);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(TextButton));
      await tester.pump();
      expect(container.read(runBoardNavigationProvider).visible, isTrue);
      repository.board = RunBoardSnapshot(
        revision: 2,
        counts: const RunBoardCounts(attention: 1000, active: 0, history: 0),
        items: [],
      );
      repository.events.add(null);
      await tester.pumpAndSettle();
      expect(find.text('999+'), findsOneWidget);
      repository.error = const RunBoardUpdateRequired();
      repository.events.add(null);
      await tester.pumpAndSettle();
      expect(find.text('?'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const SizedBox.shrink(),
        ),
      );
      await tester.pumpAndSettle();
      expect(repository.watchers, 0);
    },
  );
}
