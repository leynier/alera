import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/orchestration/application/workflow_catalog_providers.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_catalog_pane.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/run_board_widget_harness.dart';
import '../support/workflow_catalog_fixture.dart';

void main() {
  testWidgets('failed save preserves edit and navigation retains draft', (
    tester,
  ) async {
    final repository = CatalogTestRepository();
    final container = ProviderContainer(
      overrides: [
        workflowCatalogRepositoryProvider.overrideWithValue(repository),
        workbenchControllerProvider.overrideWith(BoardTestWorkbench.new),
      ],
    );
    addTearDown(container.dispose);
    Widget app(Widget child) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAleraDarkTheme(),
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpWidget(app(const WorkflowCatalogPane()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feature Delivery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit Personal'));
    await tester.pumpAndSettle();
    final input = find.widgetWithText(TextField, 'portable document');
    await tester.enterText(input, 'retained draft');
    repository.failure = StateError(
      'The recipe changed. Refresh before saving.',
    );
    await tester.tap(find.text('Save Personal'));
    await tester.pumpAndSettle();
    expect(find.text('retained draft'), findsOneWidget);
    expect(repository.saves, 1);
    await tester.pumpWidget(app(const SizedBox()));
    await tester.pumpWidget(app(const WorkflowCatalogPane()));
    await tester.pumpAndSettle();
    expect(find.text('retained draft'), findsOneWidget);
    await tester.tap(find.text('Discard Edit'));
    await tester.pumpAndSettle();
    expect(container.read(workflowCatalogDraftProvider), isNull);
  });

  testWidgets('editing cannot overwrite a different personal id', (
    tester,
  ) async {
    final repository = CatalogTestRepository()..validatedId = 'another-id';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workflowCatalogRepositoryProvider.overrideWithValue(repository),
          workbenchControllerProvider.overrideWith(BoardTestWorkbench.new),
        ],
        child: MaterialApp(
          theme: buildAleraDarkTheme(),
          home: const Scaffold(body: WorkflowCatalogPane()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Feature Delivery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit Personal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Personal'));
    await tester.pumpAndSettle();
    expect(repository.saves, 0);
    expect(find.textContaining('Keep the recipe id'), findsOneWidget);
  });
}
