import 'package:alera/src/features/orchestration/application/workflow_catalog_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/workflow_catalog_fixture.dart';

void main() {
  test('confirmed saves never replace another session or an advanced base', () {
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
    expect(drafts.reconcileSaved(submitted, saved), isNull);
    expect(container.read(workflowCatalogDraftProvider), same(other));
    drafts.retain(submitted);
    final reconciled = drafts.reconcileSaved(submitted, saved)!;
    expect(reconciled.revision, 4);
    expect(reconciled.document, 'old');
    expect(
      drafts.reconcileSaved(submitted, {...saved, 'catalogRevision': 5}),
      isNull,
    );
    expect(container.read(workflowCatalogDraftProvider), same(reconciled));
  });
}
