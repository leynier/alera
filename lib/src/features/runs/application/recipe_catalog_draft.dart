import 'package:alera/src/features/runs/application/run_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'recipe_catalog_draft.g.dart';

class RecipeCatalogEdit {
  const RecipeCatalogEdit(
    this.record,
    this.document,
    this.revision,
    this.workspaceId,
    this.session,
  );
  final Map<String, Object?> record;
  final String document;
  final int? revision;
  final String? workspaceId;
  final Object session;
}

// One user-owned draft survives navigating between Settings sections. It is
// not keyed by execution workspace and holds no processes or subscriptions.
@Riverpod(keepAlive: true)
class RecipeCatalogDraft extends _$RecipeCatalogDraft {
  @override
  RecipeCatalogEdit? build() => null;

  void retain(RecipeCatalogEdit? draft) => state = draft;

  Future<RecipeCatalogEdit?> reconcileSaved(
    RecipeCatalogEdit? submitted,
    Map<String, Object?> record,
  ) async {
    if (!ref.mounted) return null;
    final current = state;
    if (submitted == null ||
        current == null ||
        !identical(current.session, submitted.session) ||
        !identical(current.record, submitted.record) ||
        current.revision != submitted.revision) {
      return null;
    }
    if (submitted.revision == null && current.document != submitted.document) {
      try {
        final validated = await ref
            .read(recipeRepositoryProvider)
            .validate(current.document);
        if (!ref.mounted ||
            !identical(state, current) ||
            (validated['recipe']! as Map)['id'] !=
                (record['recipe']! as Map)['id']) {
          return null;
        }
      } catch (_) {
        // An invalid or renamed copy must remain create-only until the user
        // explicitly saves or reconciles that newer document.
        return null;
      }
    }
    final reconciled = RecipeCatalogEdit(
      record,
      current.document,
      record['catalogRevision']! as int,
      current.workspaceId,
      current.session,
    );
    state = reconciled;
    return reconciled;
  }

  void clearIfCurrent(RecipeCatalogEdit? submitted) {
    if (ref.mounted && identical(state, submitted)) state = null;
  }
}
