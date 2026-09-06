part of 'workflow_catalog_pane.dart';

extension _WorkflowCatalogRecovery on _WorkflowCatalogPaneState {
  Future<void> _reviewCurrent() => _run(() async {
    final submitted = ref.read(workflowCatalogDraftProvider);
    if (submitted == null) return;
    final review = await _repository.reviewPersonal(_document.text);
    if (!mounted ||
        !identical(ref.read(workflowCatalogDraftProvider), submitted)) {
      return;
    }
    if (submitted.revision != null &&
        review['id'] != _object(submitted.record['source'])['id']) {
      throw StateError(
        'Keep the recipe id when editing. Use Copy To Personal for a new id.',
      );
    }
    if (review['missing'] == true) {
      _change(
        () => _notice = submitted.revision == null
            ? 'No Personal recipe with this id exists. Your draft is unchanged; retry Save Personal to create it.'
            : 'Current Personal recipe is unavailable. Your draft is preserved.',
      );
      return;
    }
    _change(() {
      _recovery = review;
      _recoveryDraft = submitted;
    });
    if (review['matches'] == true) {
      _useReviewedRecipe(useCurrent: true, alreadySaved: true);
    }
  });

  void _useReviewedRecipe({
    required bool useCurrent,
    bool alreadySaved = false,
  }) {
    final review = _recovery;
    final submitted = _recoveryDraft;
    if (review == null ||
        submitted == null ||
        !identical(ref.read(workflowCatalogDraftProvider), submitted)) {
      return;
    }
    final record = _object(review['record']);
    final drafts = ref.read(workflowCatalogDraftProvider.notifier);
    final reconciled = drafts.reconcileSaved(submitted, record);
    if (reconciled == null) return;
    _change(() {
      _selected = record;
      _editRevision = record['catalogRevision']! as int;
      _recovery = null;
      _recoveryDraft = null;
      if (useCurrent) {
        _editing = false;
        _document.text = review['document']! as String;
      }
      _notice = alreadySaved
          ? 'Personal recipe is already saved. No write was repeated.'
          : useCurrent
          ? 'Current Personal version loaded.'
          : 'Draft preserved on the reviewed revision. Save Personal to write your changes; newer changes will still be rejected.';
    });
    if (useCurrent) drafts.clearIfCurrent(reconciled);
  }
}
