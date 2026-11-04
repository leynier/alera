import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:test/test.dart';

AgentChatTurn _failed(Map<String, Object?> fields) => AgentChatTurn.fromJson(
  <String, Object?>{'turnId': 'turn-1', 'status': 'failed', ...fields},
);

void main() {
  test(
    'a classified failure leads with guidance and keeps the provider text',
    () {
      final turn = _failed(<String, Object?>{
        'failureClass': 'usage_limit',
        'errorMessage': 'You hit your limit. Try again at 3pm.',
      });
      expect(turn.failureClass, AgentChatFailureClass.usageLimit);
      expect(
        agentChatTurnFailureMessage(turn),
        "The provider's usage limit was reached. Send the message again once "
        'the limit resets.\nYou hit your limit. Try again at 3pm.',
      );
    },
  );

  test('each class reads from its snake_case wire name', () {
    for (final (wire, failureClass) in <(String, AgentChatFailureClass)>[
      ('usage_limit', AgentChatFailureClass.usageLimit),
      ('context_window_full', AgentChatFailureClass.contextWindowFull),
      ('auth', AgentChatFailureClass.auth),
      ('previous_turn_active', AgentChatFailureClass.previousTurnActive),
      ('attachment_unreadable', AgentChatFailureClass.attachmentUnreadable),
      ('billing', AgentChatFailureClass.unknown),
    ]) {
      final turn = _failed(<String, Object?>{'failureClass': wire});
      expect(turn.failureClass, failureClass, reason: wire);
      expect(agentChatTurnFailureMessage(turn), isNotEmpty);
    }
  });

  test('an unclassified failure keeps only the provider text', () {
    expect(
      agentChatTurnFailureMessage(
        _failed(<String, Object?>{'errorMessage': 'model unavailable'}),
      ),
      'model unavailable',
    );
    expect(
      agentChatTurnFailureMessage(_failed(<String, Object?>{})),
      'The turn failed.',
    );
    expect(
      agentChatTurnFailureMessage(
        _failed(<String, Object?>{'failureClass': 'auth'}),
      ),
      'The provider rejected its sign-in. Sign in to the provider again, '
      'then retry.',
    );
  });
}
