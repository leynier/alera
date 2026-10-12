import 'dart:async';

import 'package:alera/src/features/runs/application/recipe_catalog_draft.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alera/src/features/runs/application/run_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recipe_catalog_fixture.dart';

void main() {
  for (final invalid in [false, true]) {
    test(
      'changed copy stays create-only when identity cannot match, invalid=$invalid',
      () async {
        final repository = CatalogTestRepository()
          ..validatedId = 'new-copy'
          ..validationFailure = invalid ? StateError('Invalid recipe') : null;
        final container = ProviderContainer(
          overrides: [recipeRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);
        final drafts = container.read(recipeCatalogDraftProvider.notifier);
        final session = Object();
        final submitted = RecipeCatalogEdit(
          recipeCatalogRecord,
          'submitted',
          null,
          null,
          session,
        );
        final current = RecipeCatalogEdit(
          recipeCatalogRecord,
          'changed',
          null,
          null,
          session,
        );
        drafts.retain(current);
        expect(
          await drafts.reconcileSaved(submitted, {
            ...recipeCatalogRecord,
            'catalogRevision': 4,
          }),
          isNull,
        );
        expect(container.read(recipeCatalogDraftProvider), same(current));
        expect(current.revision, isNull);
      },
    );
  }

  test('late copy identity validation cannot replace newer typing', () async {
    final pending = Completer<Map<String, Object?>>();
    final repository = CatalogTestRepository()..pendingValidation = pending;
    final container = ProviderContainer(
      overrides: [recipeRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final drafts = container.read(recipeCatalogDraftProvider.notifier);
    final session = Object();
    final submitted = RecipeCatalogEdit(
      recipeCatalogRecord,
      'submitted',
      null,
      null,
      session,
    );
    drafts.retain(
      RecipeCatalogEdit(recipeCatalogRecord, 'changed', null, null, session),
    );
    final reconciliation = drafts.reconcileSaved(submitted, {
      ...recipeCatalogRecord,
      'catalogRevision': 4,
    });
    final newer = RecipeCatalogEdit(
      recipeCatalogRecord,
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
    expect(container.read(recipeCatalogDraftProvider), same(newer));
  });

  test(
    'confirmed saves never replace another session or an advanced base',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final drafts = container.read(recipeCatalogDraftProvider.notifier);
      final submitted = RecipeCatalogEdit(
        recipeCatalogRecord,
        'old',
        3,
        null,
        Object(),
      );
      final other = RecipeCatalogEdit(
        recipeCatalogRecord,
        'other',
        null,
        null,
        Object(),
      );
      final saved = {...recipeCatalogRecord, 'catalogRevision': 4};
      drafts.retain(other);
      expect(await drafts.reconcileSaved(submitted, saved), isNull);
      expect(container.read(recipeCatalogDraftProvider), same(other));
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
      expect(container.read(recipeCatalogDraftProvider), same(reconciled));
    },
  );
}
