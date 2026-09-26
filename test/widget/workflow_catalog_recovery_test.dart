import 'dart:async';

import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/orchestration/application/workflow_catalog_providers.dart';
import 'package:alera/src/features/orchestration/presentation/workflow_catalog_pane.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/run_board_widget_harness.dart';
import '../support/workflow_catalog_fixture.dart';

Map<String, Object?> _review({bool matches = false}) => {
  'id': 'feature-delivery',
  'record': {...workflowCatalogRecord, 'catalogRevision': 4},
  'document': 'current document',
  'diff': '-current document\n+local draft',
  'matches': matches,
};

Widget _app(ProviderContainer container) => UncontrolledProviderScope(
  container: container,
  child: MaterialApp(
    theme: buildAleraDarkTheme(),
    home: const Scaffold(body: WorkflowCatalogPane()),
  ),
);

Future<ProviderContainer> _open(
  WidgetTester tester,
  CatalogTestRepository repository, {
  bool copy = false,
}) async {
  final container = ProviderContainer(
    overrides: [
      workflowCatalogRepositoryProvider.overrideWithValue(repository),
      workbenchControllerProvider.overrideWith(BoardTestWorkbench.new),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(_app(container));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Feature Delivery'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(copy ? 'Copy To Personal' : 'Edit Personal'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextField, 'portable document'),
    'local draft',
  );
  return container;
}

void main() {
  testWidgets('recovery cannot retarget an existing Personal edit', (
    tester,
  ) async {
    final repository = CatalogTestRepository()
      ..personalReview = {..._review(), 'id': 'different'};
    final container = await _open(tester, repository);
    await tester.tap(find.text('Review Current Recipe'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Keep the recipe id'), findsOneWidget);
    expect(container.read(workflowCatalogDraftProvider)!.revision, 3);
    expect(find.text('Keep My Draft'), findsNothing);
    expect(repository.saves, 0);
  });

  for (final copy in [false, true]) {
    testWidgets(
      'divergent current recipe requires explicit reconciliation, copy=$copy',
      (tester) async {
        final repository = CatalogTestRepository()..personalReview = _review();
        final container = await _open(tester, repository, copy: copy);
        repository.failure = StateError('Refresh before saving');
        await tester.tap(find.text('Save Personal'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Review Current Recipe'));
        await tester.pumpAndSettle();
        expect(repository.saves, 1);
        expect(
          container.read(workflowCatalogDraftProvider)!.revision,
          copy ? isNull : 3,
        );
        expect(find.text('local draft'), findsOneWidget);
        await tester.ensureVisible(find.text('Keep My Draft'));
        await tester.tap(find.text('Keep My Draft'));
        await tester.pumpAndSettle();
        expect(container.read(workflowCatalogDraftProvider)!.revision, 4);
        expect(find.text('local draft'), findsOneWidget);
        repository.failure = null;
        repository.requiredRevision = 4;
        await tester.ensureVisible(find.text('Save Personal'));
        await tester.tap(find.text('Save Personal'));
        await tester.pumpAndSettle();
        expect(repository.savedRevisions, [copy ? null : 3, 4]);
        expect(find.text('Personal recipe saved.'), findsOneWidget);
      },
    );

    testWidgets(
      'committed timeout is confirmed without another write, copy=$copy',
      (tester) async {
        final repository = CatalogTestRepository()
          ..personalReview = _review(matches: true);
        final container = await _open(tester, repository, copy: copy);
        repository.failure = TimeoutException('Response lost');
        await tester.tap(find.text('Save Personal'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Review Current Recipe'));
        await tester.pumpAndSettle();
        expect(repository.saves, 1);
        expect(container.read(workflowCatalogDraftProvider), isNull);
        expect(find.textContaining('No write was repeated'), findsOneWidget);
        expect(find.textContaining('Catalog Revision 4'), findsOneWidget);
      },
    );
  }

  testWidgets('missing copy candidate keeps create semantics', (tester) async {
    final repository = CatalogTestRepository()
      ..personalReview = {'id': 'candidate', 'missing': true};
    final container = await _open(tester, repository, copy: true);
    await tester.tap(find.text('Review Current Recipe'));
    await tester.pumpAndSettle();
    expect(container.read(workflowCatalogDraftProvider)!.revision, isNull);
    expect(find.text('local draft'), findsOneWidget);
    await tester.tap(find.text('Save Personal'));
    await tester.pumpAndSettle();
    expect(repository.savedRevisions, [null]);
  });

  testWidgets('use current version explicitly replaces the retained text', (
    tester,
  ) async {
    final repository = CatalogTestRepository()..personalReview = _review();
    final container = await _open(tester, repository);
    await tester.tap(find.text('Review Current Recipe'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Use Current Version'));
    await tester.tap(find.text('Use Current Version'));
    await tester.pumpAndSettle();
    expect(repository.saves, 0);
    expect(container.read(workflowCatalogDraftProvider), isNull);
    expect(find.text('Current Personal version loaded.'), findsOneWidget);
    await tester.ensureVisible(find.text('Edit Personal'));
    await tester.tap(find.text('Edit Personal'));
    await tester.pumpAndSettle();
    expect(find.text('current document'), findsOneWidget);
  });

  testWidgets('late review cannot replace a reopened newer draft', (
    tester,
  ) async {
    final pending = Completer<Map<String, Object?>>();
    final repository = CatalogTestRepository()..pendingReview = pending;
    final container = await _open(tester, repository);
    await tester.tap(find.text('Review Current Recipe'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(container));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'local draft'),
      'newer draft',
    );
    pending.complete(_review(matches: true));
    await tester.pumpAndSettle();
    expect(find.text('newer draft'), findsOneWidget);
    expect(container.read(workflowCatalogDraftProvider)!.revision, 3);
    expect(repository.saves, 0);
    expect(tester.takeException(), isNull);
  });
}
