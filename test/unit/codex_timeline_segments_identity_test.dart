import 'package:alera/src/features/codex_chat/domain/codex_chat_models.dart';
import 'package:alera/src/features/codex_chat/domain/codex_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('segmented timelines match canonical history identities', () {
    final timeline = CodexTimelineCells.segmented(
      history: <CodexTimelineCell>[
        _cell('history-item', itemId: 'shared-item'),
        _cell('history-prefixed', itemId: 'prefixed'),
        _cell('item-from-id'),
      ],
      live: const <CodexTimelineCell>[],
    );

    expect(
      timeline.historyContainsExactIdentity(
        _cell('replacement', itemId: 'shared-item'),
      ),
      isTrue,
    );
    expect(
      timeline.historyContainsExactIdentity(
        _cell('replacement-from-id', itemId: 'from-id'),
      ),
      isTrue,
    );
    expect(
      timeline.historyContainsExactIdentity(_cell('item-prefixed')),
      isTrue,
    );
    expect(timeline.historyContainsExactIdentity(_cell('unrelated')), isFalse);
  });
}

CodexTimelineCell _cell(String id, {String? itemId}) =>
    CodexTimelineCell.fromJson(<String, Object?>{
      'id': id,
      'itemId': ?itemId,
      'kind': 'assistantMessage',
    });
