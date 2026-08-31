import 'package:alera_mobile/src/features/codex_chat/application/mobile_codex_composer_draft_store.dart';
import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_composer_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first binding preserves retry IDs and explicit close removes them', () {
    final store = MobileCodexComposerDraftStore();
    final attempts = store.messageAttemptsFor('host', 'tab', null);
    attempts.retainForRetry('same', 'first-id');
    attempts.retainForRetry('same', 'second-id');
    final pending = store.submissionIdsFor('host', 'tab', null)
      ..['send'] = 'id';
    store.write('host', 'tab', const MobileCodexComposerDraft());
    expect(store.submissionIdsFor('host', 'tab', 'created'), same(pending));
    expect(store.submissionIdsFor('other', 'tab', 'created'), isEmpty);
    expect(store.submissionIdsFor('host', 'other', 'created'), isEmpty);
    expect(store.submissionIdsFor('host', 'tab', 'different'), isEmpty);
    expect(store.messageAttemptsFor('host', 'tab', 'created'), same(attempts));
    expect(
      store.messageAttemptsFor('host', 'tab', 'created').claim('same', 'new'),
      'first-id',
    );
    expect(
      store.messageAttemptsFor('host', 'tab', 'different').claim('same', 'new'),
      'new',
    );
    store.remove('host', 'tab');
    expect(
      store.messageAttemptsFor('host', 'tab', 'created').claim('same', 'new'),
      'new',
    );
    expect(store.submissionIdsFor('host', 'tab', 'created'), isEmpty);
  });
}
