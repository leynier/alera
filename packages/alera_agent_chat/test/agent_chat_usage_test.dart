import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

AgentChatUsage _usage(Map<String, Object?> tokens) =>
    AgentChatUsage.fromJson(<String, Object?>{'tokens': tokens});

void main() {
  test('the auto-compact point marks where along the window it lies', () {
    final usage = _usage(<String, Object?>{
      'context': 50000,
      'contextWindow': 200000,
      'autoCompact': 150000,
    });
    expect(usage.contextTokens, 50000);
    expect(usage.contextWindow, 200000);
    expect(usage.autoCompactTokens, 150000);
    expect(usage.contextFraction, 0.25);
    expect(usage.autoCompactFraction, 0.75);
  });

  test('an auto-compact point outside the window has no tick', () {
    for (final tokens in <Map<String, Object?>>[
      <String, Object?>{'contextWindow': 200000, 'autoCompact': 200000},
      <String, Object?>{'contextWindow': 200000, 'autoCompact': 250000},
      <String, Object?>{'contextWindow': 200000, 'autoCompact': 0},
      <String, Object?>{'autoCompact': 150000},
      <String, Object?>{'contextWindow': 0, 'autoCompact': 150000},
      <String, Object?>{'contextWindow': 200000},
    ]) {
      expect(_usage(tokens).autoCompactFraction, isNull, reason: '$tokens');
    }
    expect(const AgentChatUsage().autoCompactTokens, isNull);
  });

  test('the auto-compact note names the point', () {
    expect(
      agentChatAutoCompactNote('150,000'),
      'Compacts automatically at about 150,000 tokens.',
    );
  });
}
