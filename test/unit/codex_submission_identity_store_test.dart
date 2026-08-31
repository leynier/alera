import 'package:alera/src/features/codex_chat/application/codex_composer_draft_store.dart';
import 'package:alera/src/features/codex_chat/domain/codex_composer_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first binding preserves retry IDs and explicit close removes them', () {
    final store = CodexComposerDraftStore();
    final attempts = store.messageAttemptsFor('tab', null);
    attempts.retainForRetry('same', 'first-id');
    attempts.retainForRetry('same', 'second-id');
    final pending = store.submissionIdsFor('tab', null)..['send'] = 'id';
    store.write('tab', const CodexComposerDraft());
    expect(store.submissionIdsFor('tab', 'created'), same(pending));
    expect(store.submissionIdsFor('other', 'created'), isEmpty);
    expect(store.submissionIdsFor('tab', 'different'), isEmpty);
    expect(store.messageAttemptsFor('tab', 'created'), same(attempts));
    expect(
      store.messageAttemptsFor('tab', 'created').claim('same', 'new'),
      'first-id',
    );
    expect(
      store.messageAttemptsFor('tab', 'different').claim('same', 'new'),
      'new',
    );
    store.remove('tab');
    expect(
      store.messageAttemptsFor('tab', 'created').claim('same', 'new'),
      'new',
    );
    expect(store.submissionIdsFor('tab', 'created'), isEmpty);
  });
}
