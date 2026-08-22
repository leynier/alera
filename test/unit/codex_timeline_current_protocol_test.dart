import 'package:alera/src/features/codex_chat/domain/codex_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _message(String method, Map<String, Object?> params) =>
    <String, Object?>{'method': method, 'params': params};

void main() {
  final now = DateTime.utc(2026, 8, 2, 12);

  test('turn completion computes duration when the server omits it', () {
    var cells = CodexTimelineReducer.reduce(
      const <CodexTimelineCell>[],
      _message('turn/started', <String, Object?>{
        'turn': <String, Object?>{'id': 'turn-1'},
      }),
      now: now,
    );
    cells = CodexTimelineReducer.reduce(
      cells,
      _message('turn/completed', <String, Object?>{
        'turn': <String, Object?>{'id': 'turn-1'},
      }),
      now: now.add(const Duration(milliseconds: 375)),
    );
    expect(cells.single.metadata['computedDurationMs'], 375);
  });

  test('joins structured item content into markdown', () {
    final cells = CodexTimelineReducer.reduce(
      const <CodexTimelineCell>[],
      _message('item/completed', <String, Object?>{
        'turnId': 'turn-1',
        'item': <String, Object?>{
          'id': 'answer-1',
          'type': 'agentMessage',
          'content': <Object?>[
            'First paragraph',
            <String, Object?>{'text': 'Second paragraph'},
          ],
        },
      }),
      now: now,
    );
    expect(cells.single.markdownText, 'First paragraph\nSecond paragraph');
  });
}
