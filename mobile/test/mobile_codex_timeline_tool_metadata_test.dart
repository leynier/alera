import 'package:alera_mobile/src/features/codex_chat/domain/mobile_codex_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile keeps dynamic tool output structured in legacy snapshots', () {
    final state = MobileCodexState.fromSnapshot(<String, Object?>{
      'events': <Object?>[
        <String, Object?>{
          'method': 'item/completed',
          'params': <String, Object?>{
            'turnId': 'turn-tools',
            'item': <String, Object?>{
              'id': 'dynamic',
              'type': 'dynamicToolCall',
              'tool': 'workspace.inspect',
              'contentItems': <Object?>[
                <String, Object?>{'type': 'inputText', 'text': 'done'},
              ],
              'status': 'completed',
            },
          },
        },
      ],
    });

    final cell = state.timelineCells.single;
    expect(cell.metadata['contentItems'], isA<List>());
    expect(cell.metadata['detailsSource'], 'contentItems');
    expect(cell.detailsText, isNull);
  });

  test('mobile keeps non-string legacy tool output structured', () {
    final state = MobileCodexState.fromSnapshot(<String, Object?>{
      'events': <Object?>[
        <String, Object?>{
          'method': 'item/completed',
          'params': <String, Object?>{
            'turnId': 'turn-tools',
            'item': <String, Object?>{
              'id': 'legacy-output',
              'type': 'dynamicToolCall',
              'tool': 'legacy.inspect',
              'output': <String, Object?>{
                'records': <Object?>[1, 2],
              },
              'status': 'completed',
            },
          },
        },
      ],
    });

    final cell = state.timelineCells.single;
    expect(cell.detailsText, isNull);
    expect(cell.metadata['detailsSource'], 'output');
    expect(cell.metadata['output'], <String, Object?>{
      'records': <Object?>[1, 2],
    });
  });
}
