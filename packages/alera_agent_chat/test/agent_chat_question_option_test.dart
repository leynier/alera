import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

void main() {
  test('option previews arrive verbatim and blank ones are dropped', () {
    const preview =
        '\n  **Proposed change**\n\n```ts\n\tconst enabled = true;\n```\n  ';
    final question = AgentChatQuestion.fromJson(<String, Object?>{
      'id': 'Approach',
      'header': 'Approach',
      'question': 'Which approach?',
      'options': <Object?>[
        <String, Object?>{
          'label': 'Flag',
          'description': '',
          'preview': preview,
        },
        <String, Object?>{'label': 'Config', 'description': 'Use config'},
        <String, Object?>{'label': 'Env', 'preview': '   \n'},
        <String, Object?>{'label': 'Other', 'preview': 42},
        'Plain',
      ],
    });
    expect(question.options.map((option) => option.preview), <String?>[
      preview,
      null,
      null,
      null,
      null,
    ]);
    expect(question.options.first.description, isEmpty);
    expect(question.options.first.answerValue, 'Flag');
    expect(question.allowCustomAnswer, isFalse);
  });
}
