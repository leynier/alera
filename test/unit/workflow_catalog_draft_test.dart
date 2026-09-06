import 'dart:async';

import 'package:alera/src/features/orchestration/application/workflow_catalog_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/workflow_catalog_fixture.dart';

void main() {
  for (final invalid in [false, true]) {
    test(
      'changed copy stays create-only when identity cannot match, invalid=$invalid',
      () async {
        final repository = CatalogTestRepository()
          ..validatedId = 'new-copy'
          ..validationFailure = invalid ? StateError('Invalid recipe') : null;
        final container = ProviderContainer(
          overrides: [
            workflowCatalogRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(container.dispose);
        final drafts = container.read(workflowCatalogDraftProvider.notifier);
        final session = Object();
        final submitted = WorkflowCatalogEdit(
          workflowCatalogRecord,
          'submitted',
          null,
          null,
          session,
        );
        final current = WorkflowCatalogEdit(
          workflowCatalogRecord,
          'changed',
          null,
          null,
          session,
        );
        drafts.retain(current);
        expect(
          await drafts.reconcileSaved(submitted, {
            ...workflowCatalogRecord,
            'catalogRevision': 4,
          }),
          isNull,
        );
        expect(container.read(workflowCatalogDraftProvider), same(current));
        expect(current.revision, isNull);
      },
    );
  }

  test('late copy identity validation cannot replace newer typing', () async {
    final pending = Completer<Map<String, Object?>>();
    final repository = CatalogTestRepository()..pendingValidation = pending;
    final container = ProviderContainer(
      overrides: [
        workflowCatalogRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final drafts = container.read(workflowCatalogDraftProvider.notifier);
    final session = Object();
    final submitted = WorkflowCatalogEdit(
      workflowCatalogRecord,
      'submitted',
      null,
      null,
      session,
    );
    drafts.retain(
      WorkflowCatalogEdit(
        workflowCatalogRecord,
        'changed',
        null,
        null,
        session,
      ),
    );
    final reconciliation = drafts.reconcileSaved(submitted, {
      ...workflowCatalogRecord,
      'catalogRevision': 4,
    });
    final newer = WorkflowCatalogEdit(
      workflowCatalogRecord,
      'changed again',
      null,
      null,
      session,
    );
    drafts.retain(newer);
    pending.complete({
      'recipe': {'id': 'feature-delivery'},
    });
    expect(await reconciliation, isNull);
    expect(container.read(workflowCatalogDraftProvider), same(newer));
  });

  test(
    'confirmed saves never replace another session or an advanced base',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final drafts = container.read(workflowCatalogDraftProvider.notifier);
      final submitted = WorkflowCatalogEdit(
        workflowCatalogRecord,
        'old',
        3,
        null,
        Object(),
      );
      final other = WorkflowCatalogEdit(
        workflowCatalogRecord,
        'other',
        null,
        null,
        Object(),
      );
      final saved = {...workflowCatalogRecord, 'catalogRevision': 4};
      drafts.retain(other);
      expect(await drafts.reconcileSaved(submitted, saved), isNull);
      expect(container.read(workflowCatalogDraftProvider), same(other));
      drafts.retain(submitted);
      final reconciled = (await drafts.reconcileSaved(submitted, saved))!;
      expect(reconciled.revision, 4);
      expect(reconciled.document, 'old');
      expect(
        await drafts.reconcileSaved(submitted, {
          ...saved,
          'catalogRevision': 5,
        }),
        isNull,
      );
      expect(container.read(workflowCatalogDraftProvider), same(reconciled));
    },
  );
}
