import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

AgentChatItem _plan({
  String? title,
  String text = '',
  String? explanation,
  List<AgentChatPlanStep> steps = const <AgentChatPlanStep>[],
}) => AgentChatItem(
  id: 'plan',
  type: .plan,
  status: .completed,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  title: title,
  text: text,
  explanation: explanation,
  planSteps: steps,
  data: const <String, Object?>{'raw': 'must-not-survive'},
  input: const <String, Object?>{'providerPayload': 'must-not-survive'},
);

void main() {
  test('plan task brief uses canonical fields and numbers nonblank steps consecutively', () {
    final brief = agentChatPlanTaskBrief(
      _plan(
        text: '  Plan body  ',
        explanation: '  Why this helps  ',
        steps: const <AgentChatPlanStep>[
          AgentChatPlanStep(step: ' First ', status: .pending),
          AgentChatPlanStep(step: ' ', status: .pending),
          AgentChatPlanStep(step: ' Second ', status: .completed),
        ],
      ),
    );
    expect(
      brief,
      'Implement the following plan.\n\nWhy this helps\n\nPlan body\n\nSteps:\n1. First\n2. Second',
    );
    expect(brief, isNot(contains('must-not-survive')));
    expect(
      agentChatPlanTaskBrief(_plan(explanation: ' ')),
      'Implement the following plan.',
    );
  });

  test('plan task title prefers the explicit title and strips leading markup from body', () {
    expect(
      agentChatPlanTaskTitle(_plan(title: ' A title ', text: '# Ignored')),
      'A title',
    );
    expect(
      agentChatPlanTaskTitle(_plan(text: '\n  #-* A plan\nLater')),
      'A plan',
    );
    expect(agentChatPlanTaskTitle(_plan(text: ' \n#- *\n')), 'Implement Plan');
  });

  test('long plan titles remain at most eighty Unicode characters', () {
    final title = agentChatPlanTaskTitle(
      _plan(title: List.filled(90, '😀').join()),
    );
    expect(title.runes.length, 80);
    expect(title.endsWith('…'), isTrue);
    expect(title.runes.take(79), everyElement(0x1f600));
  });
}
