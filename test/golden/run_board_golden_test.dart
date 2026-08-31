import 'package:alchemist/alchemist.dart';
import 'package:alera/src/features/orchestration/application/run_board_navigation.dart';
import 'package:alera/src/features/orchestration/infra/runtime_run_board_repository.dart';
import 'package:alera/src/features/orchestration/presentation/run_board_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/run_board_fixtures.dart';
import '../support/run_board_widget_harness.dart';
import 'alera_golden_harness.dart';

void main() {
  runAleraGoldenTests(() {
    for (final scenario in [
      (
        name: 'run_board_overview',
        width: 1100.0,
        height: 800.0,
        run: true,
        task: false,
        scale: 1.0,
        error: false,
      ),
      (
        name: 'run_board_inspector',
        width: 1100.0,
        height: 900.0,
        run: true,
        task: true,
        scale: 1.0,
        error: false,
      ),
      (
        name: 'run_board_compact_scaled',
        width: 420.0,
        height: 720.0,
        run: true,
        task: false,
        scale: 2.0,
        error: false,
      ),
      (
        name: 'run_board_inspector_scaled',
        width: 520.0,
        height: 900.0,
        run: true,
        task: true,
        scale: 1.5,
        error: false,
      ),
      (
        name: 'run_board_update_required',
        width: 980.0,
        height: 720.0,
        run: false,
        task: false,
        scale: 1.0,
        error: true,
      ),
    ]) {
      goldenTest(
        scenario.name,
        fileName: scenario.name,
        constraints: BoxConstraints.tightFor(
          width: scenario.width,
          height: scenario.height,
        ),
        pumpBeforeTest: (tester) async {
          await tester.pumpAndSettle();
        },
        builder: () {
          final repository = BoardTestRepository();
          if (scenario.error) repository.error = const RunBoardUpdateRequired();
          final container = boardContainer(repository);
          addTearDown(container.dispose);
          addTearDown(repository.dispose);
          final navigation = container.read(runBoardNavigationProvider.notifier)
            ..open();
          if (scenario.run) navigation.selectRun('run-1');
          if (scenario.task) navigation.selectTask('task-2');
          return UncontrolledProviderScope(
            container: container,
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scenario.scale)),
                child: const Material(child: RunBoardPage()),
              ),
            ),
          );
        },
      );
    }
  });
}
