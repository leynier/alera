import 'package:alchemist/alchemist.dart';
import 'package:alera/src/features/orchestration/application/workflow_catalog_providers.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_catalog_pane.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/run_board_widget_harness.dart';
import '../support/workflow_catalog_fixture.dart';
import 'alera_golden_harness.dart';

void main() {
  runAleraGoldenTests(() {
    for (final width in [1100.0, 420.0]) {
      goldenTest(
        'Workflow catalog at $width',
        fileName: width == 1100
            ? 'workflow_catalog_desktop'
            : 'workflow_catalog_compact',
        constraints: BoxConstraints.tightFor(width: width, height: 850),
        pumpBeforeTest: (tester) async {
          await tester.pumpAndSettle();
          await tester.tap(find.text('Feature Delivery'));
          await tester.pumpAndSettle();
        },
        builder: () => ProviderScope(
          overrides: [
            workflowCatalogRepositoryProvider.overrideWithValue(
              CatalogTestRepository(),
            ),
            workbenchControllerProvider.overrideWith(BoardTestWorkbench.new),
          ],
          child: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(width == 420 ? 1.5 : 1)),
              child: const Material(child: WorkflowCatalogPane()),
            ),
          ),
        ),
      );
    }
  });
}
